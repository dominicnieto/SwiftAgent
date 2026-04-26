import Foundation
import Testing

@testable import SwiftAgent

struct AnthropicProviderReplayTests {
  @Test func anthropicConfigurationMatchesALMProviderSurface() {
    let customURL = URL(string: "https://example.com")!
    let model = AnthropicLanguageModel(baseURL: customURL, apiKey: "test-key", model: "claude-test")

    #expect(model.baseURL.absoluteString.hasSuffix("/"))
    #expect(model.model == "claude-test")
  }

  @Test func anthropicProviderRespondsThroughMainSessionAndHTTPClient() async throws {
    let replay = ReplayHTTPClient<[String: JSONValue]>(recordedResponse: .init(body: """
    {
      "id": "msg_1",
      "type": "message",
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "Hello from Claude"
        }
      ],
      "model": "claude-test",
      "stop_reason": "end_turn",
      "usage": {
        "input_tokens": 4,
        "output_tokens": 5
      }
    }
    """))
    let model = AnthropicLanguageModel(
      apiKey: "test-key",
      model: "claude-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    let response = try await session.respond(to: "Hello")

    #expect(response.content == "Hello from Claude")
    #expect(response.responseMetadata?.id == "msg_1")
    #expect(response.responseMetadata?.providerName == "Anthropic")
    #expect(response.responseMetadata?.modelID == "claude-test")
    #expect(response.tokenUsage?.totalTokens == 9)
    let requests = await replay.recordedRequests()
    #expect(requests.first?.path == "v1/messages")
  }

  @Test func anthropicProviderSendsInstructionsOptionsStructuredSchemaAndImages() async throws {
    let replay = ReplayHTTPClient<[String: JSONValue]>(recordedResponse: .init(body: """
    {
      "id": "msg_structured",
      "type": "message",
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "{\\"summary\\":\\"clear\\",\\"temperatureCelsius\\":19}"
        }
      ],
      "model": "claude-test",
      "stop_reason": "end_turn"
    }
    """))
    let model = AnthropicLanguageModel(
      apiKey: "test-key",
      model: "claude-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model, instructions: "Be concise.")
    let image = Transcript.ImageSegment(data: Data([0x04, 0x05, 0x06]), mimeType: "image/png")
    var options = GenerationOptions(temperature: 0.4, maximumResponseTokens: 32)
    options[custom: AnthropicLanguageModel.self] = .init(
      topK: 40,
      metadata: .init(userID: "test-user-id"),
      toolChoice: .disabled,
      thinking: .init(budgetTokens: 128),
      extraBody: ["service_tier": .string("standard")],
    )

    let response = try await session.respond(
      to: "Summarize this weather image.",
      image: image,
      generating: ProviderReplayForecast.self,
      options: options,
    )

    #expect(response.content.summary == "clear")
    #expect(response.content.temperatureCelsius == 19)
    let body = try await requestBodyDictionary(from: replay)
    #expect(body["model"] == .string("claude-test"))
    #expect(body["temperature"] == .double(0.4))
    #expect(body["max_tokens"] == .int(32))
    #expect(body["top_k"] == .int(40))
    #expect(body["metadata"] == .object(["user_id": .string("test-user-id")]))
    #expect(body["tool_choice"] == .object(["type": .string("none")]))
    #expect(body["thinking"] == .object(["type": .string("enabled"), "budget_tokens": .int(128)]))
    #expect(body["service_tier"] == .string("standard"))
    let messages = try #require(body["messages"]?.arrayValue)
    #expect(messages.containsJSONObject { object in
      guard object["role"] == .string("user"), case let .array(content)? = object["content"] else {
        return false
      }
      return content.containsJSONObject { $0["type"] == .string("image") }
    })
  }

  @Test func anthropicProviderStreamsTextThroughMainSessionAndHTTPClient() async throws {
    let replay = ReplayHTTPClient<[String: JSONValue]>(recordedResponse: .init(body: """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_stream","type":"message","role":"assistant","content":[],"model":"claude-test","stop_reason":null,"usage":{"input_tokens":1,"output_tokens":0}}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let model = AnthropicLanguageModel(
      apiKey: "test-key",
      model: "claude-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    var snapshots: [LanguageModelSession.ResponseStream<String>.Snapshot] = []
    for try await snapshot in session.streamResponse(to: "Hello") {
      snapshots.append(snapshot)
    }

    #expect(snapshots.compactMap(\.content) == ["Hel", "Hello", "Hello"])
    #expect(session.transcript.lastResponseEntry()?.text == "Hello")
    #expect(session.responseMetadata?.id == "msg_stream")
    #expect(session.responseMetadata?.providerName == "Anthropic")
    #expect(session.responseMetadata?.modelID == "claude-test")
    let body = try await requestBodyDictionary(from: replay)
    #expect(body["stream"] == .bool(true))
  }

  @Test func anthropicProviderStreamsStructuredOutputThroughPartialDecoder() async throws {
    let replay = ReplayHTTPClient<[String: JSONValue]>(recordedResponse: .init(body: """
    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{\\"summary\\":\\"windy\\","}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\\"temperatureCelsius\\":12}"}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let model = AnthropicLanguageModel(
      apiKey: "test-key",
      model: "claude-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    var snapshots: [LanguageModelSession.ResponseStream<ProviderReplayForecast>.Snapshot] = []
    for try await snapshot in session.streamResponse(
      to: "Provide a short weather forecast.",
      generating: ProviderReplayForecast.self,
    ) {
      snapshots.append(snapshot)
    }

    let final = try #require(snapshots.last?.content)
    #expect(final.summary == "windy")
    #expect(final.temperatureCelsius == 12)
    let body = try await requestBodyDictionary(from: replay)
    #expect(body["tools"] == nil)
  }

  @Test func anthropicProviderStreamsToolCallsThinkingAndUsageThroughMainSession() async throws {
    let replay = ReplayHTTPClient<[String: JSONValue]>(recordedResponses: [
      .init(body: #"""
      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Need weather"}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"encrypted-thinking"}}

      event: content_block_start
      data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_weather","name":"get_weather","input":{}}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"city\":"}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"Spokane\"}"}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":1}

      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":12,"output_tokens":8}}

      event: message_stop
      data: {"type":"message_stop"}

      """#),
      .init(body: #"""
      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Weather in Spokane: Sunny"}}

      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":18,"output_tokens":6}}

      event: message_stop
      data: {"type":"message_stop"}

      """#),
    ])
    let model = AnthropicLanguageModel(
      apiKey: "test-key",
      model: "claude-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model, tools: [WeatherTool()])

    var finalContent: String?
    for try await snapshot in session.streamResponse(to: "What is the weather?") {
      finalContent = snapshot.content ?? finalContent
    }

    #expect(finalContent == "Weather in Spokane: Sunny")
    #expect(session.tokenUsage?.totalTokens == 44)
    #expect(session.transcript.entries.contains { entry in
      if case let .reasoning(reasoning) = entry {
        return reasoning.summary == ["Need weather"] && reasoning.encryptedReasoning == "encrypted-thinking"
      }
      return false
    })
    #expect(session.transcript.entries.contains { entry in
      if case .toolCalls = entry { return true }
      return false
    })
    #expect(session.transcript.entries.contains { entry in
      if case .toolOutput = entry { return true }
      return false
    })

    let requests = await replay.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[1].body["stream"] == .bool(true))
  }

  @Test func anthropicProviderExecutesToolsThroughMainSessionPolicy() async throws {
    let replay = ReplayHTTPClient<[String: JSONValue]>(recordedResponses: [
      .init(body: """
      {
        "id": "msg_tool",
        "type": "message",
        "role": "assistant",
        "content": [
          {
            "type": "tool_use",
            "id": "toolu_weather",
            "name": "get_weather",
            "input": {
              "city": "Spokane"
            }
          }
        ],
        "model": "claude-test",
        "stop_reason": "tool_use"
      }
      """),
      .init(body: """
      {
        "id": "msg_final",
        "type": "message",
        "role": "assistant",
        "content": [
          {
            "type": "text",
            "text": "Weather in Spokane: Sunny"
          }
        ],
        "model": "claude-test",
        "stop_reason": "end_turn"
      }
      """),
    ])
    let model = AnthropicLanguageModel(
      apiKey: "test-key",
      model: "claude-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model, tools: [WeatherTool()])

    let response = try await session.respond(to: "What is the weather?")

    #expect(response.content == "Weather in Spokane: Sunny")
    let requests = await replay.recordedRequests()
    #expect(requests.count == 2)
    #expect(session.transcript.entries.contains { entry in
      if case .toolCalls = entry { return true }
      return false
    })
    #expect(session.transcript.entries.contains { entry in
      if case .toolOutput = entry { return true }
      return false
    })
  }
}

private func requestBodyDictionary(
  from replay: ReplayHTTPClient<[String: JSONValue]>,
) async throws -> [String: JSONValue] {
  let requests = await replay.recordedRequests()
  return try #require(requests.first?.body)
}

private extension JSONValue {
  var arrayValue: [JSONValue]? {
    guard case let .array(value) = self else { return nil }
    return value
  }
}

private extension [JSONValue] {
  func containsJSONObject(_ predicate: ([String: JSONValue]) -> Bool) -> Bool {
    contains { value in
      guard case let .object(object) = value else { return false }
      return predicate(object)
    }
  }
}
