// By Dennis Müller

import Foundation
import FoundationModels
import SwiftAgent
@preconcurrency import SwiftAnthropic

extension AnthropicAdapter {
  func handleMessageStart(
    _ payload: MessageStreamResponse,
    includeThinking: Bool,
    structuredOutputTypeName: String?,
    structuredToolName: String?,
    messageState: inout StreamingMessageState?,
    reasoningState: inout StreamingReasoningState?,
    generatedTranscript: inout Transcript,
    entryIndices: inout [String: Int],
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) throws {
    reasoningState = nil
    if includeThinking {
      let reasoningEntry = Transcript.Reasoning(
        id: UUID().uuidString,
        summary: [],
        encryptedReasoning: nil,
        status: .inProgress,
      )
      let reasoningEntryIndex = appendEntry(
        .reasoning(reasoningEntry),
        to: &generatedTranscript,
        entryIndices: &entryIndices,
        continuation: continuation,
      )
      reasoningState = StreamingReasoningState(
        entryIndex: reasoningEntryIndex,
        summaryText: "",
        encryptedReasoning: nil,
      )
    }

    let responseId = payload.message?.id ?? UUID().uuidString
    let response = Transcript.Response(
      id: responseId,
      segments: [],
      status: .inProgress,
    )

    let entryIndex = appendEntry(
      .response(response),
      to: &generatedTranscript,
      entryIndices: &entryIndices,
      continuation: continuation,
    )

    messageState = StreamingMessageState(
      entryIndex: entryIndex,
      responseId: responseId,
      status: .inProgress,
      structuredOutputTypeName: structuredOutputTypeName,
      structuredToolName: structuredToolName,
    )
  }

  func handleContentBlockStart(
    _ payload: MessageStreamResponse,
    structuredToolName: String?,
    messageState: inout StreamingMessageState?,
    reasoningState: inout StreamingReasoningState?,
    toolCallStates: inout [String: StreamingToolCallState],
    toolCallOrder: inout [String],
    toolUseIdsByIndex: inout [Int: String],
    generatedTranscript: inout Transcript,
    entryIndices: inout [String: Int],
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) throws {
    guard let index = payload.index,
          let contentBlock = payload.contentBlock else {
      return
    }

    switch contentBlock.type {
    case "text":
      if let text = contentBlock.text {
        messageState?.textFragments.assign(text, at: index)
        try updateMessageEntry(
          messageState: &messageState,
          generatedTranscript: &generatedTranscript,
          continuation: continuation,
          finalizeStructuredContent: false,
        )
      }

    case "tool_use":
      guard let name = contentBlock.name else {
        return
      }

      let toolUseId = contentBlock.id ?? UUID().uuidString
      toolUseIdsByIndex[index] = toolUseId

      if let structuredToolName, structuredToolName == name {
        messageState?.structuredToolUseId = toolUseId
        if let input = contentBlock.input,
           let arguments = try? AnthropicMessageBuilder.generatedContent(from: input) {
          let json = arguments.stableJsonString
          messageState?.structuredJSONBuffer = json
          try updateMessageEntry(
            messageState: &messageState,
            generatedTranscript: &generatedTranscript,
            continuation: continuation,
            finalizeStructuredContent: false,
          )
        }
        return
      }

      let placeholderArguments = try GeneratedContent(json: "{}")
      let toolCall = Transcript.ToolCall(
        id: toolUseId,
        callId: toolUseId,
        toolName: name,
        arguments: placeholderArguments,
        status: .inProgress,
      )

      let entry = Transcript.ToolCalls(calls: [toolCall])
      let entryIndex = appendEntry(
        .toolCalls(entry),
        to: &generatedTranscript,
        entryIndices: &entryIndices,
        continuation: continuation,
      )

      var state = StreamingToolCallState(
        toolUseId: toolUseId,
        toolName: name,
        entryIndex: entryIndex,
      )
      if let input = contentBlock.input,
         let arguments = try? AnthropicMessageBuilder.generatedContent(from: input) {
        let json = arguments.stableJsonString
        if json != "{}" {
          state.argumentsBuffer = json
          updateToolCallEntry(
            state: state,
            updatedArguments: arguments,
            generatedTranscript: &generatedTranscript,
            continuation: continuation,
            status: .completed,
          )
        }
      }

      toolCallStates[toolUseId] = state
      toolCallOrder.append(toolUseId)

    case "thinking":
      if let thinking = contentBlock.thinking {
        updateReasoningState(
          thinking: thinking,
          signature: nil,
          redacted: nil,
          reasoningState: &reasoningState,
          generatedTranscript: &generatedTranscript,
          entryIndices: &entryIndices,
          continuation: continuation,
        )
      }

    case "redacted_thinking":
      if let data = contentBlock.data {
        updateReasoningState(
          thinking: nil,
          signature: nil,
          redacted: data,
          reasoningState: &reasoningState,
          generatedTranscript: &generatedTranscript,
          entryIndices: &entryIndices,
          continuation: continuation,
        )
      }

    default:
      break
    }
  }

  func handleContentBlockDelta(
    _ payload: MessageStreamResponse,
    messageState: inout StreamingMessageState?,
    reasoningState: inout StreamingReasoningState?,
    toolCallStates: inout [String: StreamingToolCallState],
    toolUseIdsByIndex: [Int: String],
    generatedTranscript: inout Transcript,
    entryIndices: inout [String: Int],
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) throws {
    guard let index = payload.index else {
      return
    }

    if let delta = payload.delta {
      if let thinking = delta.thinking {
        updateReasoningState(
          thinking: thinking,
          signature: nil,
          redacted: nil,
          reasoningState: &reasoningState,
          generatedTranscript: &generatedTranscript,
          entryIndices: &entryIndices,
          continuation: continuation,
        )
      }

      if let signature = delta.signature {
        updateReasoningState(
          thinking: nil,
          signature: signature,
          redacted: nil,
          reasoningState: &reasoningState,
          generatedTranscript: &generatedTranscript,
          entryIndices: &entryIndices,
          continuation: continuation,
        )
      }

      if delta.type == "text_delta", let text = delta.text {
        messageState?.textFragments.append(text, at: index)
        try updateMessageEntry(
          messageState: &messageState,
          generatedTranscript: &generatedTranscript,
          continuation: continuation,
          finalizeStructuredContent: false,
        )
      }

      if delta.type == "input_json_delta", let partialJson = delta.partialJson {
        guard let toolUseId = toolUseIdsByIndex[index] else {
          return
        }

        if toolUseId == messageState?.structuredToolUseId {
          if var buffer = messageState?.structuredJSONBuffer {
            appendPartialJSON(partialJson, to: &buffer)
            messageState?.structuredJSONBuffer = buffer
          }
          try updateMessageEntry(
            messageState: &messageState,
            generatedTranscript: &generatedTranscript,
            continuation: continuation,
            finalizeStructuredContent: false,
          )
          return
        }

        guard var state = toolCallStates[toolUseId] else {
          return
        }

        var buffer = state.argumentsBuffer
        appendPartialJSON(partialJson, to: &buffer)
        state.argumentsBuffer = buffer
        toolCallStates[toolUseId] = state

        if let updatedArguments = try? GeneratedContent(json: state.argumentsBuffer) {
          updateToolCallEntry(
            state: state,
            updatedArguments: updatedArguments,
            generatedTranscript: &generatedTranscript,
            continuation: continuation,
          )
        }
      }
    }
  }

  func handleContentBlockStop(
    _ payload: MessageStreamResponse,
    messageState: inout StreamingMessageState?,
    toolCallStates: inout [String: StreamingToolCallState],
    toolUseIdsByIndex: [Int: String],
    generatedTranscript: inout Transcript,
    entryIndices: inout [String: Int],
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) throws {
    guard let index = payload.index else {
      return
    }

    if let toolUseId = toolUseIdsByIndex[index] {
      if toolUseId == messageState?.structuredToolUseId {
        try updateMessageEntry(
          messageState: &messageState,
          generatedTranscript: &generatedTranscript,
          continuation: continuation,
          finalizeStructuredContent: true,
        )
        return
      }

      guard let state = toolCallStates[toolUseId] else {
        return
      }

      do {
        let finalJSON = state.argumentsBuffer.isEmpty ? "{}" : state.argumentsBuffer
        let updatedArguments = try GeneratedContent(json: finalJSON)
        updateToolCallEntry(
          state: state,
          updatedArguments: updatedArguments,
          generatedTranscript: &generatedTranscript,
          continuation: continuation,
          status: .completed,
        )
      } catch {
        throw GenerationError.structuredContentParsingFailed(
          .init(rawContent: state.argumentsBuffer, underlyingError: error),
        )
      }
    }
  }

  func handleMessageDelta(
    _ payload: MessageStreamResponse,
    messageState: inout StreamingMessageState?,
    generatedTranscript: inout Transcript,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) {
    if let stopReason = payload.delta?.stopReason {
      messageState?.status = transcriptStatus(from: stopReason)
      if let messageState {
        updateMessageStatus(
          state: messageState,
          generatedTranscript: &generatedTranscript,
          continuation: continuation,
        )
      }
    }
  }

  func finalizeMessage(
    messageState: inout StreamingMessageState?,
    reasoningState: inout StreamingReasoningState?,
    generatedTranscript: inout Transcript,
    entryIndices: inout [String: Int],
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) throws {
    if messageState?.status == .inProgress {
      messageState?.status = .completed
    }

    try updateMessageEntry(
      messageState: &messageState,
      generatedTranscript: &generatedTranscript,
      continuation: continuation,
      finalizeStructuredContent: true,
    )

    if let status = messageState?.status, let reasoningEntryIndex = reasoningState?.entryIndex {
      _ = updateTranscriptEntry(
        at: reasoningEntryIndex,
        in: &generatedTranscript,
        continuation: continuation,
      ) { entry in
        guard case var .reasoning(reasoning) = entry else {
          return
        }

        reasoning.status = status
        entry = .reasoning(reasoning)
      }
    }

    if let state = messageState, state.structuredOutputTypeName != nil {
      if !state.textFragments.nonEmptyFragments.isEmpty {
        throw GenerationError.unexpectedTextResponse(.init())
      }

      if state.structuredContent == nil {
        throw GenerationError.unexpectedStructuredResponse(.init())
      }
    }
  }

  func executeQueuedToolCalls(
    inOrder toolCallOrder: [String],
    toolCallStates: inout [String: StreamingToolCallState],
    generatedTranscript: inout Transcript,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) async throws -> Bool {
    var didExecuteAny = false

    for identifier in toolCallOrder {
      guard var state = toolCallStates[identifier] else {
        continue
      }
      guard !state.hasInvokedTool else {
        continue
      }

      let argumentsJSON = state.argumentsBuffer.isEmpty ? "{}" : state.argumentsBuffer
      let arguments = try GeneratedContent(json: argumentsJSON)
      let toolCall = Transcript.ToolCall(
        id: state.toolUseId,
        callId: state.toolUseId,
        toolName: state.toolName,
        arguments: arguments,
        status: nil,
      )

      try await executeToolCall(
        toolCall,
        generatedTranscript: &generatedTranscript,
        continuation: continuation,
      )

      state.hasInvokedTool = true
      toolCallStates[identifier] = state
      didExecuteAny = true
    }

    return didExecuteAny
  }
}
