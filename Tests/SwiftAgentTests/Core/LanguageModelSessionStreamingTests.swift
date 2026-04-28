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

  func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
    _ = request
    return AsyncThrowingStream { continuation in
      continuation.yield(.textDelta(id: "text", delta: "A"))
      continuation.yield(.textDelta(id: "text", delta: "B"))
      continuation.yield(.textDelta(id: "text", delta: "C"))
      continuation.yield(.completed(.init(finishReason: .completed)))
      continuation.finish()
    }
  }



}
