import Foundation
import Testing

@testable import SwiftAgent

struct OpenAIProviderReplayTests {
  @Test func openAIChatCompletionsConfigurationMatchesALMProviderSurface() {
    let customURL = URL(string: "https://example.com")!
    let chat = OpenAILanguageModel(
      baseURL: customURL,
      apiKey: "test-key",
      model: "gpt-test",
      apiVariant: .chatCompletions,
    )
    let responses = OpenAILanguageModel(apiKey: "test-key", model: "gpt-test", apiVariant: .responses)

    #expect(chat.baseURL.absoluteString.hasSuffix("/"))
    #expect(chat.model == "gpt-test")
    #expect(chat.apiVariant == .chatCompletions)
    #expect(responses.apiVariant == .responses)
  }

  @Test func openAIChatCompletionsRespondsThroughMainSessionAndHTTPClient() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    {
      "id": "chatcmpl_1",
      "model": "gpt-test",
      "usage": {
        "prompt_tokens": 2,
        "completion_tokens": 3,
        "total_tokens": 5
      },
      "choices": [
        {
          "message": {
            "role": "assistant",
            "content": "Hello from Chat",
            "refusal": null,
            "tool_calls": null
          },
          "finish_reason": "stop"
        }
      ]
    }
    """))
    let model = OpenAILanguageModel(
      apiKey: "test-key",
      model: "gpt-test",
      apiVariant: .chatCompletions,
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    let response = try await session.respond(to: "Hello")

    #expect(response.content == "Hello from Chat")
    #expect(response.responseMetadata?.id == "chatcmpl_1")
    #expect(response.responseMetadata?.providerName == "OpenAI")
    #expect(response.responseMetadata?.modelID == "gpt-test")
    #expect(response.tokenUsage?.totalTokens == 5)
    let requests = await replay.recordedRequests()
    #expect(requests.first?.path == "chat/completions")
  }

  @Test func openAIChatCompletionsSendsInstructionsOptionsStructuredSchemaAndImages() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    {
      "id": "chatcmpl_structured",
      "model": "gpt-test",
      "choices": [
        {
          "message": {
            "role": "assistant",
            "content": "{\\"summary\\":\\"clear\\",\\"temperatureCelsius\\":21}",
            "refusal": null,
            "tool_calls": null
          },
          "finish_reason": "stop"
        }
      ]
    }
    """))
    let model = OpenAILanguageModel(
      apiKey: "test-key",
      model: "gpt-test",
      apiVariant: .chatCompletions,
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model, instructions: "Be concise.")
    let image = Transcript.ImageSegment(data: Data([0x01, 0x02, 0x03]), mimeType: "image/png")
    var options = GenerationOptions(temperature: 0.7, maximumResponseTokens: 50)
    options[custom: OpenAILanguageModel.self] = .init(
      topP: 0.9,
      metadata: ["suite": "provider-replay"],
      extraBody: ["user": .string("test-user-id")],
    )

    let response = try await session.respond(
      to: "Summarize this weather image.",
      image: image,
      generating: ProviderReplayForecast.self,
      options: options,
    )

    #expect(response.content.summary == "clear")
    #expect(response.content.temperatureCelsius == 21)
    let body = try await requestBodyObject(from: replay)
    #expect(body["model"] == .string("gpt-test"))
    #expect(body["temperature"] == .double(0.7))
    #expect(body["max_completion_tokens"] == .int(50))
    #expect(body["top_p"] == .double(0.9))
    #expect(body["metadata"] == .object(["suite": .string("provider-replay")]))
    #expect(body["user"] == .string("test-user-id"))
    guard case let .object(responseFormat)? = body["response_format"] else {
      Issue.record("Expected response_format for structured output")
      return
    }
    #expect(responseFormat["type"] == .string("json_schema"))
    let messages = try #require(body["messages"]?.arrayValue)
    #expect(messages.containsJSONObject { $0["role"] == .string("system") })
    #expect(messages.containsJSONObject { object in
      guard object["role"] == .string("user"), case let .array(content)? = object["content"] else {
        return false
      }
      return content.containsJSONObject { $0["type"] == .string("image_url") }
    })
  }

  @Test func openAIResponsesProviderStreamsTextThroughMainSessionAndHTTPClient() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(
      body: """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"Hel"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"lo"}

    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_stream","model":"gpt-test","usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}}}

    """,
      headers: [
        "x-request-id": "stream_req_header",
        "x-ratelimit-limit-requests": "100",
        "x-ratelimit-remaining-requests": "98",
      ],
    ))
    let model = OpenAILanguageModel(
      apiKey: "test-key",
      model: "gpt-test",
      apiVariant: .responses,
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    var snapshots: [LanguageModelSession.ResponseStream<String>.Snapshot] = []
    for try await snapshot in session.streamResponse(to: "Hello") {
      snapshots.append(snapshot)
    }

    #expect(snapshots.compactMap(\.content) == ["Hel", "Hello", "Hello"])
    #expect(session.transcript.lastResponseEntry()?.text == "Hello")
    #expect(session.responseMetadata?.id == "resp_stream")
    #expect(session.responseMetadata?.providerRequestID == "stream_req_header")
    #expect(session.responseMetadata?.modelID == "gpt-test")
    #expect(session.responseMetadata?.rateLimits["requests"]?.remaining == 98)
    #expect(session.tokenUsage?.totalTokens == 5)
    let body = try await requestBodyObject(from: replay)
    #expect(body["stream"] == .bool(true))
  }

  @Test func openAIResponsesProviderStreamsStructuredOutputThroughPartialDecoder() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"{\\"name\\":\\"Alice\\","}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"\\"age\\":28,\\"email\\":\\"alice@example.com\\"}"}

    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_structured","model":"gpt-test"}}

    """))
    let model = OpenAILanguageModel(
      apiKey: "test-key",
      model: "gpt-test",
      apiVariant: .responses,
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    var snapshots: [LanguageModelSession.ResponseStream<ProviderReplayPerson>.Snapshot] = []
    for try await snapshot in session.streamResponse(to: "Generate Alice.", generating: ProviderReplayPerson.self) {
      snapshots.append(snapshot)
    }

    let final = try #require(snapshots.last?.content)
    #expect(final.name == "Alice")
    #expect(final.age == 28)
  }

  @Test func openAIResponsesProviderStreamsToolArgumentDeltasBeforeToolOutput() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponses: [
      .init(body: #"""
      event: response.output_item.added
      data: {"type":"response.output_item.added","item":{"id":"fc_weather","type":"function_call","status":"in_progress","arguments":"","call_id":"call_weather","name":"get_weather"},"output_index":0}

      event: response.function_call_arguments.delta
      data: {"type":"response.function_call_arguments.delta","delta":"{\"city\":","item_id":"fc_weather","output_index":0}

      event: response.function_call_arguments.delta
      data: {"type":"response.function_call_arguments.delta","delta":"\"Spokane\"}","item_id":"fc_weather","output_index":0}

      event: response.function_call_arguments.done
      data: {"type":"response.function_call_arguments.done","arguments":"{\"city\":\"Spokane\"}","item_id":"fc_weather","output_index":0}

      event: response.completed
      data: {"type":"response.completed","response":{"id":"resp_tool","model":"gpt-test","usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}}

      """#),
      .init(body: #"""
      event: response.output_text.delta
      data: {"type":"response.output_text.delta","delta":"Weather in Spokane: Sunny"}

      event: response.completed
      data: {"type":"response.completed","response":{"id":"resp_final","model":"gpt-test","usage":{"input_tokens":20,"output_tokens":7,"total_tokens":27}}}

      """#),
    ])
    let model = OpenAILanguageModel(
      apiKey: "test-key",
      model: "gpt-test",
      apiVariant: .responses,
      httpClient: replay,
    )
    let session = LanguageModelSession(
      model: model,
      tools: [WeatherTool()],
      toolExecutionPolicy: .init(allowsParallelExecution: false),
    )

    var sawPartialArgumentsBeforeOutput = false
    var sawToolOutput = false
    for try await snapshot in session.streamResponse(
      to: "What is the weather?",
      options: GenerationOptions(minimumStreamingSnapshotInterval: .zero),
    ) {
      for entry in snapshot.transcript.entries {
        if case .toolOutput = entry {
          sawToolOutput = true
        }
        if case let .toolCalls(toolCalls) = entry,
           toolCalls.calls.contains(where: { $0.partialArguments?.contains(#""Spokane""#) == true }),
           sawToolOutput == false {
          sawPartialArgumentsBeforeOutput = true
        }
      }
    }

    #expect(sawPartialArgumentsBeforeOutput)
    #expect(session.transcript.entries.contains { entry in
      if case .toolOutput = entry { return true }
      return false
    })
    #expect(session.tokenUsage?.totalTokens == 42)
  }

  @Test func openAIResponsesProviderStreamsReasoningSeparatelyFromText() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: #"""
    event: response.output_item.added
    data: {"type":"response.output_item.added","item":{"id":"rs_1","type":"reasoning","summary":[{"text":"Need weather"}],"encrypted_content":"encrypted-reasoning"},"output_index":0}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"Done"}

    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_reasoning","model":"gpt-test","usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}}}

    """#))
    let model = OpenAILanguageModel(
      apiKey: "test-key",
      model: "gpt-test",
      apiVariant: .responses,
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    for try await _ in session.streamResponse(to: "Think briefly.") {}

    #expect(session.transcript.entries.contains { entry in
      if case let .reasoning(reasoning) = entry {
        return reasoning.summary == ["Need weather"] && reasoning.encryptedReasoning == "encrypted-reasoning"
      }
      return false
    })
    #expect(session.transcript.lastResponseEntry()?.text == "Done")
  }

  @Test func openAIResponseMetadataIncludesHTTPHeaders() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(
      body: """
      {
        "id": "chatcmpl_headers",
        "model": "gpt-test",
        "choices": [
          {
            "message": {
              "role": "assistant",
              "content": "Header metadata",
              "refusal": null,
              "tool_calls": null
            },
            "finish_reason": "stop"
          }
        ]
      }
      """,
      headers: [
        "x-request-id": "req_header",
        "x-ratelimit-limit-requests": "100",
        "x-ratelimit-remaining-requests": "99",
        "retry-after": "2",
      ],
    ))
    let model = OpenAILanguageModel(
      apiKey: "test-key",
      model: "gpt-test",
      apiVariant: .chatCompletions,
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    let response = try await session.respond(to: "Hello")

    #expect(response.responseMetadata?.providerRequestID == "req_header")
    #expect(response.responseMetadata?.requestID != nil)
    #expect(response.responseMetadata?.rateLimits["requests"]?.limit == 100)
    #expect(response.responseMetadata?.rateLimits["requests"]?.remaining == 99)
    #expect(response.responseMetadata?.rateLimits["requests"]?.retryAfter == 2)
  }
}

private func requestBodyObject(
  from replay: ReplayHTTPClient<JSONValue>
) async throws -> [String: JSONValue] {
  let requests = await replay.recordedRequests()
  let first = try #require(requests.first)
  guard case let .object(body) = first.body else {
    Issue.record("Expected JSON object request body")
    return [:]
  }
  return body
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
