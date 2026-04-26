import Foundation
import Testing

@testable import SwiftAgent

struct DirectProviderReplayTests {
  @Test func openResponsesProviderRespondsThroughCanonicalSessionAndHTTPClient() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    {
      "id": "resp_1",
      "output": [],
      "output_text": "Hello from Open Responses"
    }
    """))
    let model = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    let response = try await session.respond(to: "Hello")

    #expect(response.content == "Hello from Open Responses")
    let requests = await replay.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.path == "responses")
    guard case let .object(body)? = requests.first?.body else {
      Issue.record("Expected Open Responses request body object")
      return
    }
    #expect(body["model"] == .string("openai/gpt-test"))
    #expect(body["stream"] == .bool(false))
  }

  @Test func openResponsesProviderStreamsTextThroughCanonicalSessionAndHTTPClient() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"Hel"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"lo"}

    event: response.completed
    data: {"type":"response.completed"}

    """))
    let model = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    var snapshots: [LanguageModelSession.ResponseStream<String>.Snapshot] = []
    for try await snapshot in session.streamResponse(to: "Hello") {
      snapshots.append(snapshot)
    }

    #expect(snapshots.map(\.content) == ["Hel", "Hello", "Hello"])
    #expect(session.transcript.lastResponseEntry()?.text == "Hello")
    let requests = await replay.recordedRequests()
    guard case let .object(body)? = requests.first?.body else {
      Issue.record("Expected Open Responses streaming request body object")
      return
    }
    #expect(body["stream"] == .bool(true))
  }

  @Test func openResponsesProviderStreamsToolCallsThroughCanonicalSessionPolicy() async throws {
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
      data: {"type":"response.completed","response":{"id":"resp_tool","model":"openai/gpt-test","usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}}

      """#),
      .init(body: #"""
      event: response.output_text.delta
      data: {"type":"response.output_text.delta","delta":"Weather in Spokane: Sunny"}

      event: response.completed
      data: {"type":"response.completed","response":{"id":"resp_final","model":"openai/gpt-test","usage":{"input_tokens":20,"output_tokens":7,"total_tokens":27}}}

      """#),
    ])
    let model = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model, tools: [WeatherTool()])

    var finalContent: String?
    for try await snapshot in session.streamResponse(to: "What is the weather?") {
      finalContent = snapshot.content ?? finalContent
    }

    #expect(finalContent == "Weather in Spokane: Sunny")
    #expect(session.transcript.entries.contains { entry in
      if case .toolCalls = entry { return true }
      return false
    })
    #expect(session.transcript.entries.contains { entry in
      if case .toolOutput = entry { return true }
      return false
    })
    #expect(session.tokenUsage?.totalTokens == 42)

    let requests = await replay.recordedRequests()
    guard requests.count == 2 else {
      Issue.record("Expected two Open Responses requests, got \(requests.count)")
      return
    }
    guard case let .object(secondBody) = requests[1].body,
      case let .array(input)? = secondBody["input"]
    else {
      Issue.record("Expected second Open Responses request input")
      return
    }
    #expect(input.contains { item in
      if case let .object(object) = item,
        object["type"] == .string("function_call"),
        object["call_id"] == .string("call_weather")
      {
        return true
      }
      return false
    })
    #expect(input.contains { item in
      if case let .object(object) = item,
        object["type"] == .string("function_call_output"),
        object["call_id"] == .string("call_weather")
      {
        return true
      }
      return false
    })
  }

  @Test func openResponsesProviderExecutesToolsThroughCanonicalSessionPolicy() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponses: [
      .init(body: """
      {
        "id": "resp_tool",
        "output": [
          {
            "type": "function_call",
            "call_id": "call_weather",
            "name": "get_weather",
            "arguments": "{\\"city\\":\\"Spokane\\"}"
          }
        ],
        "output_text": null
      }
      """),
      .init(body: """
      {
        "id": "resp_final",
        "output": [],
        "output_text": "Weather in Spokane: Sunny"
      }
      """),
    ])
    let model = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
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

  @Test func openAIChatCompletionsProviderRespondsThroughCanonicalSessionAndHTTPClient() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    {
      "id": "chatcmpl_1",
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
    let requests = await replay.recordedRequests()
    #expect(requests.first?.path == "chat/completions")
  }

  @Test func anthropicProviderRespondsThroughCanonicalSessionAndHTTPClient() async throws {
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
      "stop_reason": "end_turn"
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
    let requests = await replay.recordedRequests()
    #expect(requests.first?.path == "v1/messages")
  }

  @Test func anthropicProviderStreamsTextThroughCanonicalSessionAndHTTPClient() async throws {
    let replay = ReplayHTTPClient<[String: JSONValue]>(recordedResponse: .init(body: """
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

    #expect(snapshots.map(\.content) == ["Hel", "Hello", "Hello"])
    #expect(session.transcript.lastResponseEntry()?.text == "Hello")
    let requests = await replay.recordedRequests()
    #expect(requests.first?.body["stream"] == .bool(true))
  }

  @Test func anthropicProviderStreamsToolCallsThinkingAndUsageThroughCanonicalSession() async throws {
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

  @Test func anthropicProviderExecutesToolsThroughCanonicalSessionPolicy() async throws {
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

private struct WeatherTool: Tool {
  var name: String { "get_weather" }
  var description: String { "Returns weather for a city." }

  @Generable
  struct Arguments {
    var city: String
  }

  func call(arguments: Arguments) async throws -> String {
    "Sunny in \(arguments.city)"
  }
}
