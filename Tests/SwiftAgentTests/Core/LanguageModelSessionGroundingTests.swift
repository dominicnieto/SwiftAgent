// By Dennis Muller

import Foundation
@testable import SwiftAgent
import Testing

struct LanguageModelSessionGroundingTests {
  @SessionSchema
  struct GroundedSchema {
    @Grounding(Date.self) var currentDate
  }

  @Test func directSessionRespondStoresTypedGroundingsInTranscript() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    {
      "id": "resp_grounded",
      "output": [],
      "output_text": "Grounded response"
    }
    """))
    let model = OpenResponsesLanguageModel(
      apiKey: "test-key",
      model: "gpt-test",
      httpClient: replay,
    )
    let schema = GroundedSchema()
    let session = LanguageModelSession(model: model)
    let date = Date(timeIntervalSince1970: 1_234)

    let response = try await session.respond(
      to: "What day is it?",
      schema: schema,
      groundingWith: [.currentDate(date)],
    ) { input, sources in
      PromptTag("context") {
        for source in sources {
          if case let .currentDate(date) = source {
            "Current date: \(date)"
          }
        }
      }

      PromptTag("input") {
        input
      }
    }

    #expect(response.content == "Grounded response")
    let resolved = try schema.resolve(session.transcript)
    let prompt = try #require(resolved.compactMap { entry -> Transcript.Resolved<GroundedSchema>.Prompt? in
      guard case let .prompt(prompt) = entry else { return nil }
      return prompt
    }.first)
    #expect(prompt.input == "What day is it?")
    #expect(prompt.sources == [.currentDate(date)])
    #expect(prompt.prompt.contains("Current date:"))
  }

  @Test func directSessionStreamingStoresTypedGroundingsInTranscript() async throws {
    let replay = ReplayHTTPClient<JSONValue>(recordedResponse: .init(body: """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"Grounded"}

    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_grounded_stream"}}

    """))
    let model = OpenResponsesLanguageModel(
      apiKey: "test-key",
      model: "gpt-test",
      httpClient: replay,
    )
    let schema = GroundedSchema()
    let session = LanguageModelSession(model: model)
    let date = Date(timeIntervalSince1970: 5_678)

    let stream = try session.streamResponse(
      to: "Stream with context.",
      schema: schema,
      groundingWith: [.currentDate(date)],
      options: GenerationOptions(minimumStreamingSnapshotInterval: .zero),
    ) { input, sources in
      PromptTag("context") {
        for source in sources {
          if case let .currentDate(date) = source {
            "Current date: \(date)"
          }
        }
      }

      PromptTag("input") {
        input
      }
    }

    for try await _ in stream {}

    let resolved = try schema.resolve(session.transcript)
    let prompt = try #require(resolved.compactMap { entry -> Transcript.Resolved<GroundedSchema>.Prompt? in
      guard case let .prompt(prompt) = entry else { return nil }
      return prompt
    }.first)
    #expect(prompt.input == "Stream with context.")
    #expect(prompt.sources == [.currentDate(date)])
  }
}
