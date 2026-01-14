// By Dennis Müller

import Foundation
import FoundationModels
import SwiftAgent
@preconcurrency import SwiftAnthropic

typealias Transcript = SwiftAgent.Transcript

extension AnthropicAdapter {
  public func streamResponse(
    to prompt: Transcript.Prompt,
    generating type: (some StructuredOutput).Type?,
    using model: Model = .default,
    including transcript: Transcript,
    options: AnthropicGenerationOptions,
  ) -> AsyncThrowingStream<AdapterUpdate, any Error> {
    let setup = AsyncThrowingStream<AdapterUpdate, any Error>.makeStream()

    AgentLog.start(
      model: String(describing: model),
      toolNames: tools.map(\.name),
      promptPreview: prompt.input,
    )

    let task = Task<Void, Never> {
      do {
        try options.validate(for: model)
      } catch {
        AgentLog.error(error, context: "Invalid generation options")
        setup.continuation.finish(throwing: error)
        return
      }

      do {
        try await runStreamResponse(
          transcript: transcript,
          generating: type,
          using: model,
          options: options,
          continuation: setup.continuation,
        )

        AgentLog.finish()
        setup.continuation.finish()
      } catch {
        AgentLog.error(error, context: "streaming response")
        setup.continuation.finish(throwing: error)
        return
      }

      setup.continuation.finish()
    }

    setup.continuation.onTermination = { _ in
      task.cancel()
    }

    return setup.stream
  }

  private func runStreamResponse(
    transcript: Transcript,
    generating type: (some StructuredOutput).Type?,
    using model: Model,
    options: AnthropicGenerationOptions,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) async throws {
    var generatedTranscript = Transcript()
    var entryIndices: [String: Int] = [:]
    var messageState: StreamingMessageState?
    var reasoningState: StreamingReasoningState?
    var toolCallStates: [String: StreamingToolCallState] = [:]
    var toolCallOrder: [String] = []
    var toolUseIdsByIndex: [Int: String] = [:]

    let structuredOutputTypeName = type?.name
    let structuredToolName = try structuredOutputToolName(for: structuredOutputTypeName)

    let allowedSteps = 20
    var currentStep = 0

    stepLoop: for _ in 0..<allowedSteps {
      try Task.checkCancellation()
      currentStep += 1
      AgentLog.stepRequest(step: currentStep)

      let accumulatedTranscript = Transcript(entries: transcript.entries + generatedTranscript.entries)
      let request = try messageRequest(
        including: accumulatedTranscript,
        generating: type,
        using: model,
        options: options,
        streamResponses: true,
      )

      let eventStream = httpClient.stream(
        path: messagesPath,
        method: .post,
        headers: [:],
        body: request,
      )

      let decoder = AnthropicMessageStreamEventDecoder()
      var responseCompleted = false
      var shouldContinueLoop = false

      do {
        streamLoop: for try await event in eventStream {
          try Task.checkCancellation()
          guard let decoded = try decoder.decodeEvent(from: event) else {
            continue
          }

          if let error = decoded.payload.error {
            throw GenerationError.providerError(
              message: error.message,
              code: nil,
              type: error.type,
              parameter: nil,
            )
          }

          if let usage = decoded.payload.usage,
             let tokenUsage = tokenUsage(from: usage) {
            continuation.yield(.tokenUsage(tokenUsage))
          }

          switch decoded.type {
          case MessageStreamResponse.StreamEvent.messageStart.rawValue:
            try handleMessageStart(
              decoded.payload,
              structuredOutputTypeName: structuredOutputTypeName,
              structuredToolName: structuredToolName,
              messageState: &messageState,
              generatedTranscript: &generatedTranscript,
              entryIndices: &entryIndices,
              continuation: continuation,
            )

          case MessageStreamResponse.StreamEvent.contentBlockStart.rawValue:
            try handleContentBlockStart(
              decoded.payload,
              structuredToolName: structuredToolName,
              messageState: &messageState,
              reasoningState: &reasoningState,
              toolCallStates: &toolCallStates,
              toolCallOrder: &toolCallOrder,
              toolUseIdsByIndex: &toolUseIdsByIndex,
              generatedTranscript: &generatedTranscript,
              entryIndices: &entryIndices,
              continuation: continuation,
            )

          case MessageStreamResponse.StreamEvent.contentBlockDelta.rawValue:
            try handleContentBlockDelta(
              decoded.payload,
              messageState: &messageState,
              reasoningState: &reasoningState,
              toolCallStates: &toolCallStates,
              toolUseIdsByIndex: toolUseIdsByIndex,
              generatedTranscript: &generatedTranscript,
              entryIndices: &entryIndices,
              continuation: continuation,
            )

          case MessageStreamResponse.StreamEvent.contentBlockStop.rawValue:
            try handleContentBlockStop(
              decoded.payload,
              messageState: &messageState,
              toolCallStates: &toolCallStates,
              toolUseIdsByIndex: toolUseIdsByIndex,
              generatedTranscript: &generatedTranscript,
              entryIndices: &entryIndices,
              continuation: continuation,
            )

          case MessageStreamResponse.StreamEvent.messageDelta.rawValue:
            handleMessageDelta(
              decoded.payload,
              messageState: &messageState,
              generatedTranscript: &generatedTranscript,
              continuation: continuation,
            )

          case MessageStreamResponse.StreamEvent.messageStop.rawValue:
            responseCompleted = true
            try finalizeMessage(
              messageState: &messageState,
              generatedTranscript: &generatedTranscript,
              entryIndices: &entryIndices,
              continuation: continuation,
            )
            break streamLoop

          default:
            continue
          }
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw GenerationError.fromStream(error, httpErrorMapper: GenerationError.from)
      }

      try Task.checkCancellation()

      guard responseCompleted else {
        continue stepLoop
      }

      if !toolCallOrder.isEmpty {
        let didExecuteAny = try await executeQueuedToolCalls(
          inOrder: toolCallOrder,
          toolCallStates: &toolCallStates,
          generatedTranscript: &generatedTranscript,
          continuation: continuation,
        )

        if didExecuteAny {
          shouldContinueLoop = true
        }
      }

      if shouldContinueLoop {
        continue stepLoop
      }

      return
    }
  }
}

private extension AnthropicAdapter {
  func handleMessageStart(
    _ payload: MessageStreamResponse,
    structuredOutputTypeName: String?,
    structuredToolName: String?,
    messageState: inout StreamingMessageState?,
    generatedTranscript: inout Transcript,
    entryIndices: inout [String: Int],
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) throws {
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
          messageState?.structuredJSONBuffer = arguments.stableJsonString
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
        status: nil,
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
        state.argumentsBuffer = arguments.stableJsonString
        updateToolCallEntry(
          state: state,
          updatedArguments: arguments,
          generatedTranscript: &generatedTranscript,
          continuation: continuation,
        )
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
          messageState?.structuredJSONBuffer.append(partialJson)
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

        state.argumentsBuffer.append(partialJson)
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
        let updatedArguments = try GeneratedContent(json: state.argumentsBuffer)
        updateToolCallEntry(
          state: state,
          updatedArguments: updatedArguments,
          generatedTranscript: &generatedTranscript,
          continuation: continuation,
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

    if let state = messageState, let _ = state.structuredOutputTypeName {
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
      guard !state.argumentsBuffer.isEmpty else {
        continue
      }

      let arguments = try GeneratedContent(json: state.argumentsBuffer)
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
}

private struct StreamingMessageState {
  var entryIndex: Int
  var responseId: String
  var status: Transcript.Status
  var structuredOutputTypeName: String?
  var structuredToolName: String?
  var structuredToolUseId: String?
  var structuredJSONBuffer: String
  var structuredContent: GeneratedContent?
  var textFragments: ContentFragmentBuffer

  init(
    entryIndex: Int,
    responseId: String,
    status: Transcript.Status,
    structuredOutputTypeName: String?,
    structuredToolName: String?,
  ) {
    self.entryIndex = entryIndex
    self.responseId = responseId
    self.status = status
    self.structuredOutputTypeName = structuredOutputTypeName
    self.structuredToolName = structuredToolName
    structuredToolUseId = nil
    structuredJSONBuffer = ""
    structuredContent = nil
    textFragments = ContentFragmentBuffer()
  }
}

private struct StreamingReasoningState {
  var entryIndex: Int
  var summaryText: String
  var encryptedReasoning: String?
}

private struct StreamingToolCallState {
  var toolUseId: String
  var toolName: String
  var argumentsBuffer: String
  var entryIndex: Int
  var hasInvokedTool: Bool

  init(
    toolUseId: String,
    toolName: String,
    entryIndex: Int,
  ) {
    self.toolUseId = toolUseId
    self.toolName = toolName
    argumentsBuffer = ""
    self.entryIndex = entryIndex
    hasInvokedTool = false
  }
}

private struct ContentFragmentBuffer {
  private var fragments: [String] = []

  mutating func append(
    _ text: String,
    at index: Int,
  ) {
    ensureCapacity(for: index)
    fragments[index].append(text)
  }

  mutating func assign(
    _ text: String,
    at index: Int,
  ) {
    ensureCapacity(for: index)
    fragments[index] = text
  }

  func joined(
    separator: String = "",
  ) -> String {
    fragments.joined(separator: separator)
  }

  var nonEmptyFragments: [String] {
    fragments.filter { !$0.isEmpty }
  }

  private mutating func ensureCapacity(
    for index: Int,
  ) {
    if fragments.count <= index {
      fragments.append(contentsOf: Array(repeating: "", count: index - fragments.count + 1))
    }
  }
}
