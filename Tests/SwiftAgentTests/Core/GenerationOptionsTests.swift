import Foundation
import Testing

@testable import SwiftAgent

struct GenerationOptionsTests {
  @Test func customOptionsRoundTripForModelType() {
    var options = GenerationOptions(temperature: 0.7, maximumResponseTokens: 128)
    options[custom: MockLanguageModel.self] = .init(extraBody: ["trace": .bool(true)])

    let custom = options[custom: MockLanguageModel.self]

    #expect(custom?.extraBody?["trace"] == .bool(true))
    #expect(options.temperature == 0.7)
    #expect(options.maximumResponseTokens == 128)
  }

  @Test func customOptionsAreIsolatedByModelType() {
    var options = GenerationOptions()
    options[custom: MockLanguageModel.self] = .init(extraBody: ["model": .string("mock")])

    let otherOptions = options[custom: OtherMockLanguageModel.self]

    #expect(otherOptions == nil)
    #expect(options[custom: MockLanguageModel.self]?.extraBody?["model"] == .string("mock"))
  }

  @Test func customOptionsParticipateInEquality() {
    var lhs = GenerationOptions(temperature: 0.4)
    var rhs = GenerationOptions(temperature: 0.4)

    lhs[custom: MockLanguageModel.self] = .init(extraBody: ["enabled": .bool(true)])
    rhs[custom: MockLanguageModel.self] = .init(extraBody: ["enabled": .bool(true)])

    #expect(lhs == rhs)

    rhs[custom: MockLanguageModel.self] = .init(extraBody: ["enabled": .bool(false)])

    #expect(lhs != rhs)
  }

  @Test func decodingPreservesCommonOptionsAndDropsUnregisteredCustomOptions() throws {
    var options = GenerationOptions(temperature: 0.8, maximumResponseTokens: 256)
    options[custom: MockLanguageModel.self] = .init(extraBody: ["key": .string("value")])

    let data = try JSONEncoder().encode(options)
    let decoded = try JSONDecoder().decode(GenerationOptions.self, from: data)

    #expect(decoded.temperature == 0.8)
    #expect(decoded.maximumResponseTokens == 256)
    #expect(decoded[custom: MockLanguageModel.self] == nil)
  }
}

struct LanguageModelSessionTests {
  @Test func respondAddsPromptResponseAndTokenUsageToSessionState() async throws {
    let model = MockLanguageModel { prompt, options in
      let customOptions = options[custom: MockLanguageModel.self]
      #expect(prompt.description == "Hello")
      #expect(customOptions?.extraBody?["mode"] == .string("unit-test"))
      return "Hi"
    }
    let session = LanguageModelSession(model: model, instructions: "Be concise.")
    var options = GenerationOptions(temperature: 0.2)
    options[custom: MockLanguageModel.self] = .init(extraBody: ["mode": .string("unit-test")])

    let response = try await session.respond(to: "Hello", options: options)

    #expect(response.content == "Hi")
    #expect(session.isResponding == false)
    #expect(session.transcript.entries.count == 3)
    #expect(session.tokenUsage?.inputTokens == 1)
    #expect(session.tokenUsage?.outputTokens == 2)
    #expect(session.tokenUsage?.totalTokens == 3)

    guard case let .instructions(instructionsEntry) = session.transcript.entries.first else {
      Issue.record("Expected the session transcript to start with instructions")
      return
    }

    guard case let .text(instructionText) = instructionsEntry.segments.first else {
      Issue.record("Expected instructions to be recorded as text")
      return
    }

    #expect(instructionText.content == "Be concise.")

    guard case let .response(responseEntry) = session.transcript.entries.last else {
      Issue.record("Expected the final transcript entry to be a response")
      return
    }

    #expect(responseEntry.text == "Hi")
    #expect(responseEntry.status == .completed)
  }

  @Test func streamResponseYieldsTranscriptDerivedSnapshots() async throws {
    let session = LanguageModelSession(model: MockLanguageModel(streamedText: ["Hel", "Hello"]))

    var snapshots: [LanguageModelSession.ResponseStream<String>.Snapshot] = []
    for try await snapshot in session.streamResponse(to: "Say hello") {
      snapshots.append(snapshot)
    }

    #expect(snapshots.count == 3)
    #expect(snapshots.first?.content == "Hel")
    #expect(snapshots.last?.content == "Hello")
    #expect(snapshots.last?.transcript.entries.count == 2)
    #expect(session.tokenUsage?.outputTokens == 2)

    guard case let .response(responseEntry) = session.transcript.entries.last else {
      Issue.record("Expected the final transcript entry to be a response")
      return
    }

    #expect(responseEntry.text == "Hello")
    #expect(responseEntry.status == .completed)
  }
}

private struct MockLanguageModel: LanguageModel {
  struct CustomGenerationOptions: SwiftAgent.CustomGenerationOptions, Codable {
    var extraBody: [String: JSONValue]?
  }

  var responseProvider: @Sendable (Prompt, GenerationOptions) async throws -> String
  var streamedText: [String]

  init(
    streamedText: [String] = [],
    responseProvider: @escaping @Sendable (Prompt, GenerationOptions) async throws -> String = { _, _ in "Mock response" },
  ) {
    self.streamedText = streamedText
    self.responseProvider = responseProvider
  }

  func respond<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) async throws -> LanguageModelSession.Response<Content> where Content: Generable & Sendable {
    _ = session
    _ = includeSchemaInPrompt

    let text = try await responseProvider(prompt, options)
    let content = try #require(text as? Content)

    return LanguageModelSession.Response(
      content: content,
      rawContent: GeneratedContent(text),
      tokenUsage: TokenUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3),
    )
  }

  func streamResponse<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    _ = session
    _ = prompt
    _ = type
    _ = includeSchemaInPrompt
    _ = options

    let streamedText = streamedText
    let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
      Task {
        for text in streamedText {
          let content = text as? Content.PartiallyGenerated
          continuation.yield(.init(
            content: content,
            rawContent: GeneratedContent(text),
            tokenUsage: TokenUsage(outputTokens: 1),
          ))
        }
        continuation.finish()
      }
    }

    return LanguageModelSession.ResponseStream(stream: stream)
  }
}

private struct OtherMockLanguageModel: LanguageModel {
  struct CustomGenerationOptions: SwiftAgent.CustomGenerationOptions {
    var flag: Bool
  }

  func respond<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) async throws -> LanguageModelSession.Response<Content> where Content: Generable & Sendable {
    _ = session
    _ = prompt
    _ = type
    _ = includeSchemaInPrompt
    _ = options
    throw LanguageModelSession.GenerationError.decodingFailure(.init(debugDescription: "Not implemented"))
  }

  func streamResponse<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    _ = session
    _ = prompt
    _ = type
    _ = includeSchemaInPrompt
    _ = options
    return LanguageModelSession.ResponseStream(stream: AsyncThrowingStream { $0.finish() })
  }
}
