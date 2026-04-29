import Foundation
import Testing

@testable import SwiftAgent

struct LanguageModelSessionStreamingTests {
  @Test func respondWithToolOutputsAppendsOutputsAndSendsOneTurn() async throws {
    let model = ToolContinuationLanguageModel()
    let session = LanguageModelSession(model: model, tools: [LookupTool()])

    let firstTurn = try await session.respond(to: "Look up Nashville")
    let toolCall = try #require(firstTurn.transcriptEntries.compactMap { entry -> Transcript.ToolCall? in
      guard case let .toolCalls(toolCalls) = entry else { return nil }
      return toolCalls.calls.first
    }.first)

    let finalTurn = try await session.respond(with: [
      Transcript.ToolOutput(
        id: toolCall.id,
        callId: toolCall.callId,
        toolName: toolCall.toolName,
        segment: .text(.init(content: "72 F and clear")),
        status: .completed,
      ),
    ])

    #expect(finalTurn.content == "Tool said: 72 F and clear")

    let requests = model.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[1].messages.contains { message in
      message.role == .tool && message.providerMetadata["call_id"] == .string("call-lookup")
    })
  }

  @Test func streamResponseWithToolOutputsAppendsOutputsAndStreamsOneTurn() async throws {
    let model = StreamingToolContinuationLanguageModel()
    let session = LanguageModelSession(model: model, tools: [LookupTool()])

    for try await _ in session.streamResponse(to: "Look up Nashville") {}

    let toolCall = try #require(session.transcript.entries.compactMap { entry -> Transcript.ToolCall? in
      guard case let .toolCalls(toolCalls) = entry else { return nil }
      return toolCalls.calls.first
    }.first)

    var snapshots: [LanguageModelSession.ResponseStream<String>.Snapshot] = []
    for try await snapshot in session.streamResponse(with: [
      Transcript.ToolOutput(
        id: toolCall.id,
        callId: toolCall.callId,
        toolName: toolCall.toolName,
        segment: .text(.init(content: "72 F and clear")),
        status: .completed,
      ),
    ]) {
      snapshots.append(snapshot)
    }

    #expect(snapshots.compactMap(\.content).last == "Tool said: 72 F and clear")
    #expect(model.recordedRequests().count == 2)
  }

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

private final class ToolContinuationLanguageModel: LanguageModel, @unchecked Sendable {
  typealias UnavailableReason = Never

  private let requests = Locked<[ModelRequest]>([])

  func respond(to request: ModelRequest) async throws -> ModelResponse {
    requests.withLock { $0.append(request) }

    if let toolOutput = request.messages.last(where: { $0.role == .tool }) {
      let text = textContent(from: toolOutput.segments)
      return ModelResponse(content: GeneratedContent("Tool said: \(text)"), finishReason: .completed)
    }

    return ModelResponse(
      toolCalls: [ModelToolCall(call: lookupCall())],
      finishReason: .toolCalls,
    )
  }

  func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
    _ = request
    return AsyncThrowingStream { continuation in
      continuation.finish(throwing: LanguageModelContractError.neutralTurnNotImplemented(modelType: "ToolContinuationLanguageModel"))
    }
  }

  func recordedRequests() -> [ModelRequest] {
    requests.withLock { $0 }
  }
}

private final class StreamingToolContinuationLanguageModel: LanguageModel, @unchecked Sendable {
  typealias UnavailableReason = Never

  private let requests = Locked<[ModelRequest]>([])

  func respond(to request: ModelRequest) async throws -> ModelResponse {
    _ = request
    throw LanguageModelContractError.neutralTurnNotImplemented(modelType: "StreamingToolContinuationLanguageModel")
  }

  func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
    requests.withLock { $0.append(request) }

    return AsyncThrowingStream { continuation in
      if let toolOutput = request.messages.last(where: { $0.role == .tool }) {
        let text = textContent(from: toolOutput.segments)
        continuation.yield(.textDelta(id: "text", delta: "Tool said: \(text)"))
        continuation.yield(.completed(.init(finishReason: .completed)))
      } else {
        let call = lookupCall()
        continuation.yield(.toolInputStarted(.init(
          id: call.id,
          callId: call.callId,
          toolName: call.toolName,
        )))
        continuation.yield(.toolInputDelta(id: call.id, delta: #"{"query":"Nashville"}"#))
        continuation.yield(.toolInputCompleted(id: call.id))
        continuation.yield(.toolCallsCompleted([ModelToolCall(call: call)]))
        continuation.yield(.completed(.init(finishReason: .toolCalls)))
      }
      continuation.finish()
    }
  }

  func recordedRequests() -> [ModelRequest] {
    requests.withLock { $0 }
  }
}

private struct LookupTool: Tool {
  let name = "lookup"
  let description = "Looks up a value."

  @Generable
  struct Arguments {
    let query: String
  }

  func call(arguments: Arguments) async throws -> String {
    "unused"
  }
}

private func lookupCall() -> Transcript.ToolCall {
  Transcript.ToolCall(
    id: "tool-lookup",
    callId: "call-lookup",
    toolName: "lookup",
    arguments: GeneratedContent(properties: ["query": "Nashville"]),
    status: .completed,
    providerMetadata: ["mock": .object(["item_id": .string("tool-lookup")])],
  )
}

private func textContent(from segments: [Transcript.Segment]) -> String {
  segments.compactMap { segment in
    if case let .text(text) = segment {
      return text.content
    }
    return nil
  }.joined()
}
