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
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"Hel"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"lo"}

    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_stream","model":"gpt-test","usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}}}

    """))
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
    #expect(session.responseMetadata?.modelID == "gpt-test")
    #expect(session.tokenUsage?.totalTokens == 5)
    let body = try await requestBodyObject(from: replay)
    #expect(body["stream"] == .bool(true))
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
