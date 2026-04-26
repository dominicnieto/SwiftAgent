import Foundation
import Testing

@testable import SwiftAgent

struct OpenResponsesProviderReplayTests {
  @Test func openResponsesConfigurationMatchesALMProviderSurface() {
    let customURL = URL(string: "https://example.com")!
    let model = OpenResponsesLanguageModel(baseURL: customURL, apiKey: "test-key", model: "openai/gpt-test")

    #expect(model.baseURL.absoluteString.hasSuffix("/"))
    #expect(model.model == "openai/gpt-test")
  }

  @Test func openResponsesProviderRespondsThroughMainSessionAndHTTPClient() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    {
      "id": "resp_1",
      "model": "openai/gpt-test",
      "output": [],
      "output_text": "Hello from Open Responses",
      "usage": {
        "input_tokens": 3,
        "output_tokens": 4,
        "total_tokens": 7
      }
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
    #expect(response.responseMetadata?.id == "resp_1")
    #expect(response.responseMetadata?.providerName == "Open Responses")
    #expect(response.responseMetadata?.modelID == "openai/gpt-test")
    #expect(response.tokenUsage?.totalTokens == 7)
    #expect(session.responseMetadata?.id == "resp_1")
    let requests = await replay.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.path == "responses")
    let body = try await requestBodyObject(from: replay)
    #expect(body["model"] == .string("openai/gpt-test"))
    #expect(body["stream"] == .bool(false))
  }

  @Test func openResponsesProviderSendsInstructionsOptionsCustomBodyAndImages() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    {
      "id": "resp_options",
      "model": "openai/gpt-test",
      "output": [],
      "output_text": "Image noted"
    }
    """))
    let model = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model, instructions: "Be concise.")
    let image = Transcript.ImageSegment(url: URL(string: "https://example.com/weather.png")!)
    var options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 12)
    options[custom: OpenResponsesLanguageModel.self] = .init(
      toolChoice: OpenResponsesLanguageModel.CustomGenerationOptions.ToolChoice.none,
      parallelToolCalls: false,
      extraBody: ["user": .string("test-user-id")],
    )

    let response = try await session.respond(to: "Describe this image.", image: image, options: options)

    #expect(response.content == "Image noted")
    let body = try await requestBodyObject(from: replay)
    #expect(body["instructions"] == .string("Be concise."))
    #expect(body["temperature"] == .double(0.2))
    #expect(body["max_output_tokens"] == .int(12))
    #expect(body["tool_choice"] == .string("none"))
    #expect(body["parallel_tool_calls"] == .bool(false))
    #expect(body["user"] == .string("test-user-id"))
    let input = try #require(body["input"]?.arrayValue)
    #expect(input.containsJSONObject { object in
      guard object["role"] == .string("user"), case let .array(content)? = object["content"] else {
        return false
      }
      return content.containsJSONObject {
        $0["type"] == .string("input_image") && $0["image_url"] == .string("https://example.com/weather.png")
      }
    })
  }

  @Test func openResponsesProviderStreamsTextThroughMainSessionAndHTTPClient() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(
      body: """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"Hel"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"lo"}

    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_stream","model":"openai/gpt-test","usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}}}

    """,
      headers: [
        "x-request-id": "or_stream_req_header",
        "x-ratelimit-limit-requests": "50",
        "x-ratelimit-remaining-requests": "48",
      ],
    ))
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

    #expect(snapshots.compactMap(\.content) == ["Hel", "Hello", "Hello"])
    #expect(session.transcript.lastResponseEntry()?.text == "Hello")
    #expect(session.responseMetadata?.id == "resp_stream")
    #expect(session.responseMetadata?.providerRequestID == "or_stream_req_header")
    #expect(session.responseMetadata?.modelID == "openai/gpt-test")
    #expect(session.responseMetadata?.rateLimits["requests"]?.remaining == 48)
    #expect(session.tokenUsage?.totalTokens == 5)
    let body = try await requestBodyObject(from: replay)
    #expect(body["stream"] == .bool(true))
  }

  @Test func openResponsesProviderStreamsStructuredOutputThroughPartialDecoder() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"{\\"name\\":\\"Alice\\","}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"\\"age\\":28,\\"email\\":\\"alice@example.com\\"}"}

    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_structured","model":"openai/gpt-test"}}

    """))
    let model = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
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
    let body = try await requestBodyObject(from: replay)
    #expect(body["text"] != nil)
  }

  @Test func openResponsesProviderStreamsToolCallsThroughMainSessionPolicy() async throws {
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
    var sawPartialArgumentsBeforeOutput = false
    var sawToolOutput = false
    for try await snapshot in session.streamResponse(to: "What is the weather?") {
      finalContent = snapshot.content ?? finalContent
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

    #expect(finalContent == "Weather in Spokane: Sunny")
    #expect(sawPartialArgumentsBeforeOutput)
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
    #expect(input.containsJSONObject { object in
      object["type"] == .string("function_call") && object["call_id"] == .string("call_weather")
    })
    #expect(input.containsJSONObject { object in
      object["type"] == .string("function_call_output") && object["call_id"] == .string("call_weather")
    })
  }

  @Test func openResponsesProviderExecutesToolsThroughMainSessionPolicy() async throws {
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

  @Test func openResponsesResponseMetadataIncludesHTTPHeaders() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(
      body: """
      {
        "id": "resp_headers",
        "model": "openai/gpt-test",
        "output": [],
        "output_text": "Header metadata"
      }
      """,
      headers: [
        "x-request-id": "or_req_header",
        "x-ratelimit-limit-requests": "50",
        "x-ratelimit-remaining-requests": "49",
      ],
    ))
    let model = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    let response = try await session.respond(to: "Hello")

    #expect(response.responseMetadata?.providerRequestID == "or_req_header")
    #expect(response.responseMetadata?.requestID != nil)
    #expect(response.responseMetadata?.rateLimits["requests"]?.limit == 50)
    #expect(response.responseMetadata?.rateLimits["requests"]?.remaining == 49)
  }

  @Test func openResponsesHTTPErrorStatusIsSurfaced() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(
      body: #"{"error":{"message":"bad request","type":"invalid_request_error"}}"#,
      statusCode: 400,
    ))
    let model = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    do {
      _ = try await session.respond(to: "Hello")
      Issue.record("Expected HTTP 400 to throw")
    } catch let error as HTTPError {
      guard case let .unacceptableStatus(code, _) = error else {
        Issue.record("Expected unacceptable status, got \(error)")
        return
      }
      #expect(code == 400)
    }
  }

  @Test func openResponsesStreamFailureEventThrows() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    event: response.failed
    data: {"type":"response.failed","response":{"id":"resp_failed","model":"openai/gpt-test"}}

    """))
    let model = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model)

    do {
      for try await _ in session.streamResponse(to: "Hello") {}
      Issue.record("Expected stream failure to throw")
    } catch let error as LanguageModelStreamError {
      #expect(error.code == "stream_failed")
    }
  }

  @Test func openResponsesMalformedStreamedToolArgumentsThrow() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: #"""
    event: response.output_item.added
    data: {"type":"response.output_item.added","item":{"id":"fc_weather","type":"function_call","status":"in_progress","arguments":"","call_id":"call_weather","name":"get_weather"},"output_index":0}

    event: response.function_call_arguments.delta
    data: {"type":"response.function_call_arguments.delta","delta":"{\"city\": tru","item_id":"fc_weather","output_index":0}

    event: response.function_call_arguments.done
    data: {"type":"response.function_call_arguments.done","arguments":"{\"city\": tru","item_id":"fc_weather","output_index":0}

    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_tool","model":"openai/gpt-test"}}

    """#))
    let model = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
      httpClient: replay,
    )
    let session = LanguageModelSession(model: model, tools: [WeatherTool()])

    do {
      for try await _ in session.streamResponse(to: "What is the weather?") {}
      Issue.record("Expected malformed streamed tool arguments to throw")
    } catch {
      #expect(error is GeneratedContentError)
    }
  }
}

private func requestBodyObject(from replay: ReplayHTTPClient<JSONValue>) async throws -> [String: JSONValue] {
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
