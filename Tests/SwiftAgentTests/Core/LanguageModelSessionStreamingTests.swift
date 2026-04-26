import Foundation
import Testing

@testable import SwiftAgent

struct LanguageModelSessionStreamingTests {
  @Test func minimumStreamingSnapshotIntervalCoalescesIntermediateSnapshots() async throws {
    let session = LanguageModelSession(model: BurstStreamingLanguageModel())

    var snapshots: [LanguageModelSession.ResponseStream<String>.Snapshot] = []
    for try await snapshot in session.streamResponse(
      to: "Hello",
      options: GenerationOptions(minimumStreamingSnapshotInterval: .seconds(60)),
    ) {
      snapshots.append(snapshot)
    }

    #expect(snapshots.compactMap(\.content) == ["A", "ABC"])
    #expect(session.transcript.lastResponseEntry()?.text == "ABC")
  }
}

private struct BurstStreamingLanguageModel: EventStreamingLanguageModel {
  typealias UnavailableReason = Never

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
    throw LanguageModelSession.GenerationError.decodingFailure(.init(debugDescription: "Streaming-only test model"))
  }

  func streamResponse<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) -> sending LanguageModelSession.ResponseStream<Content>
    where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    _ = session
    _ = prompt
    _ = type
    _ = includeSchemaInPrompt
    _ = options
    return LanguageModelSession.ResponseStream(stream: AsyncThrowingStream { $0.finish() })
  }

  func streamEvents<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) -> AsyncThrowingStream<LanguageModelStreamEvent, any Error>
    where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    _ = session
    _ = prompt
    _ = type
    _ = includeSchemaInPrompt
    _ = options
    return AsyncThrowingStream { continuation in
      continuation.yield(.textDelta(id: "text", delta: "A"))
      continuation.yield(.textDelta(id: "text", delta: "B"))
      continuation.yield(.textDelta(id: "text", delta: "C"))
      continuation.yield(.finished(.completed))
      continuation.finish()
    }
  }
}
