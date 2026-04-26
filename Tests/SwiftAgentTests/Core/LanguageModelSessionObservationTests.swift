import Observation
import Testing

@testable import SwiftAgent

struct LanguageModelSessionObservationTests {
  @Test func transcriptObservationFiresWhenRespondMutatesTranscript() async throws {
    let session = LanguageModelSession(model: ObservationLanguageModel(responseDelay: .milliseconds(10)))
    let changed = Locked(false)

    withObservationTracking {
      _ = session.transcript
    } onChange: {
      changed.withLock { $0 = true }
    }

    _ = try await session.respond(to: "Hello")

    #expect(changed.withLock { $0 })
  }

  @Test func transcriptObservationFiresWhenStreamResponseMutatesTranscript() async throws {
    let session = LanguageModelSession(model: ObservationLanguageModel(streamDelay: .milliseconds(10)))
    let changed = Locked(false)

    withObservationTracking {
      _ = session.transcript
    } onChange: {
      changed.withLock { $0 = true }
    }

    for try await _ in session.streamResponse(to: "Hello") {}

    #expect(changed.withLock { $0 })
  }

  @Test func isRespondingObservationFiresDuringRespond() async throws {
    let session = LanguageModelSession(model: ObservationLanguageModel(responseDelay: .milliseconds(50)))
    let changed = Locked(false)

    withObservationTracking {
      _ = session.isResponding
    } onChange: {
      changed.withLock { $0 = true }
    }

    let task = Task {
      try await session.respond(to: "Hello")
    }

    #expect(try await waitUntil(session.isResponding))
    _ = try await task.value

    #expect(changed.withLock { $0 })
    #expect(session.isResponding == false)
  }

  @Test func isRespondingObservationFiresDuringStreamResponse() async throws {
    let session = LanguageModelSession(model: ObservationLanguageModel(streamDelay: .milliseconds(50)))
    let changed = Locked(false)

    withObservationTracking {
      _ = session.isResponding
    } onChange: {
      changed.withLock { $0 = true }
    }

    let stream = session.streamResponse(to: "Hello")
    let task = Task {
      for try await _ in stream {}
    }

    #expect(try await waitUntil(session.isResponding))
    _ = try await task.value

    #expect(changed.withLock { $0 })
    #expect(session.isResponding == false)
  }

  @Test func observationDoesNotFireWithoutTrackedRead() async throws {
    let session = LanguageModelSession(model: ObservationLanguageModel())
    let changed = Locked(false)

    withObservationTracking {
      // Intentionally do not read any observed session properties.
    } onChange: {
      changed.withLock { $0 = true }
    }

    _ = try await session.respond(to: "Hello")

    #expect(changed.withLock { $0 } == false)
  }
}

private func waitUntil(
  timeout: Duration = .milliseconds(500),
  pollInterval: Duration = .milliseconds(5),
  _ condition: @autoclosure () -> Bool,
) async throws -> Bool {
  let deadline = ContinuousClock.now + timeout
  while condition() == false {
    if ContinuousClock.now >= deadline {
      return false
    }
    try await Task.sleep(for: pollInterval)
  }
  return true
}

private struct ObservationLanguageModel: LanguageModel {
  typealias UnavailableReason = Never

  var responseDelay: Duration?
  var streamDelay: Duration?

  init(responseDelay: Duration? = nil, streamDelay: Duration? = nil) {
    self.responseDelay = responseDelay
    self.streamDelay = streamDelay
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

    if let responseDelay {
      try await Task.sleep(for: responseDelay)
    }

    let text = "Observed"
    let content = try #require(text as? Content)
    return LanguageModelSession.Response(content: content, rawContent: GeneratedContent(text))
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

    let streamDelay = streamDelay
    let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
      let task = Task {
        if let streamDelay {
          try await Task.sleep(for: streamDelay)
        }

        let text = "Observed"
        continuation.yield(.init(
          content: (text as? Content)?.asPartiallyGenerated(),
          rawContent: GeneratedContent(text),
        ))
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }

    return LanguageModelSession.ResponseStream(stream: stream)
  }
}
