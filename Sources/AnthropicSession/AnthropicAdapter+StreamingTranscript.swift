// By Dennis Müller

import Foundation
import FoundationModels
import SwiftAgent

extension AnthropicAdapter {
  @discardableResult
  func appendEntry(
    _ entry: Transcript.Entry,
    to generatedTranscript: inout Transcript,
    entryIndices: inout [String: Int],
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) -> Int {
    generatedTranscript.entries.append(entry)
    let index = generatedTranscript.entries.count - 1
    entryIndices[entry.id] = index
    continuation.yield(.transcript(entry))
    return index
  }

  @discardableResult
  func updateTranscriptEntry(
    at index: Int,
    in generatedTranscript: inout Transcript,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
    mutate: (inout Transcript.Entry) throws -> Void,
  ) rethrows -> Transcript.Entry {
    var entry = generatedTranscript.entries[index]
    try mutate(&entry)
    generatedTranscript.entries[index] = entry
    continuation.yield(.transcript(entry))
    return entry
  }

  func updateMessageEntry(
    messageState: inout StreamingMessageState?,
    generatedTranscript: inout Transcript,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
    finalizeStructuredContent: Bool,
  ) throws {
    guard var state = messageState else {
      return
    }

    try updateTranscriptEntry(
      at: state.entryIndex,
      in: &generatedTranscript,
      continuation: continuation,
    ) { entry in
      guard case var .response(response) = entry else {
        return
      }

      response.status = state.status

      if let typeName = state.structuredOutputTypeName {
        let combinedJSON = state.structuredJSONBuffer
        if !combinedJSON.isEmpty {
          do {
            let content = try GeneratedContent(json: combinedJSON)
            state.structuredContent = content
            response.segments = [
              .structure(
                Transcript.StructuredSegment(
                  typeName: typeName,
                  content: content,
                ),
              ),
            ]
          } catch {
            if finalizeStructuredContent {
              AgentLog.error(error, context: "structured_response_parsing")
              throw GenerationError.structuredContentParsingFailed(
                .init(rawContent: combinedJSON, underlyingError: error),
              )
            }
          }
        }
      } else {
        let fragments = state.textFragments.nonEmptyFragments
        if !fragments.isEmpty {
          response.segments = fragments.map { .text(.init(content: $0)) }
        }
      }

      entry = .response(response)
    }

    messageState = state
  }

  func updateMessageStatus(
    state: StreamingMessageState,
    generatedTranscript: inout Transcript,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) {
    _ = updateTranscriptEntry(
      at: state.entryIndex,
      in: &generatedTranscript,
      continuation: continuation,
    ) { entry in
      guard case var .response(response) = entry else {
        return
      }

      response.status = state.status
      entry = .response(response)
    }
  }

  func updateToolCallEntry(
    state: StreamingToolCallState,
    updatedArguments: GeneratedContent,
    generatedTranscript: inout Transcript,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
    status: Transcript.Status? = nil,
  ) {
    updateTranscriptEntry(
      at: state.entryIndex,
      in: &generatedTranscript,
      continuation: continuation,
    ) { entry in
      guard case var .toolCalls(toolCalls) = entry else {
        return
      }
      guard let callIndex = toolCalls.calls.firstIndex(where: { $0.id == state.toolUseId }) else {
        return
      }

      toolCalls.calls[callIndex].arguments = updatedArguments
      if let status {
        toolCalls.calls[callIndex].status = status
      }
      entry = .toolCalls(toolCalls)
    }
  }

  func updateReasoningState(
    thinking: String?,
    signature: String?,
    redacted: String?,
    reasoningState: inout StreamingReasoningState?,
    generatedTranscript: inout Transcript,
    entryIndices: inout [String: Int],
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) {
    if reasoningState == nil {
      let entry = Transcript.Reasoning(
        id: UUID().uuidString,
        summary: thinking.map { [$0] } ?? [],
        encryptedReasoning: signature ?? redacted,
        status: .inProgress,
      )

      let entryIndex = appendEntry(
        .reasoning(entry),
        to: &generatedTranscript,
        entryIndices: &entryIndices,
        continuation: continuation,
      )

      reasoningState = StreamingReasoningState(
        entryIndex: entryIndex,
        summaryText: thinking ?? "",
        encryptedReasoning: signature ?? redacted,
      )
      return
    }

    guard var state = reasoningState else {
      return
    }

    if let thinking {
      state.summaryText.append(thinking)
    }
    if let signature {
      state.encryptedReasoning = signature
    }
    if let redacted {
      state.encryptedReasoning = redacted
    }

    _ = updateTranscriptEntry(
      at: state.entryIndex,
      in: &generatedTranscript,
      continuation: continuation,
    ) { entry in
      guard case var .reasoning(reasoning) = entry else {
        return
      }

      if !state.summaryText.isEmpty {
        reasoning.summary = [state.summaryText]
      }

      reasoning.encryptedReasoning = state.encryptedReasoning
      entry = .reasoning(reasoning)
    }

    reasoningState = state
  }

  func appendPartialJSON(
    _ partial: String,
    to buffer: inout String,
  ) {
    if buffer.isEmpty || buffer == "{}" {
      buffer = partial
    } else {
      buffer.append(partial)
    }
  }
}
