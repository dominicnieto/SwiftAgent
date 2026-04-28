import Foundation

/// Shared runtime state for direct model sessions and future agent sessions.
package struct ConversationState: Sendable, Equatable {
  /// Public transcript accumulated by the runtime.
  package var transcript: Transcript
  /// Cumulative token usage across applied model turns.
  package var tokenUsage: TokenUsage?
  /// Latest merged provider response metadata.
  package var responseMetadata: ResponseMetadata?
  /// Opaque provider continuations preserved outside the public transcript.
  package var continuationStore: ProviderContinuationStore

  package var responseEntryID: String
  package var responseSegmentID: String

  package init(
    transcript: Transcript = Transcript(),
    tokenUsage: TokenUsage? = nil,
    responseMetadata: ResponseMetadata? = nil,
    continuationStore: ProviderContinuationStore = ProviderContinuationStore(),
    responseEntryID: String = UUID().uuidString,
    responseSegmentID: String = UUID().uuidString,
  ) {
    self.transcript = transcript
    self.tokenUsage = tokenUsage
    self.responseMetadata = responseMetadata
    self.continuationStore = continuationStore
    self.responseEntryID = responseEntryID
    self.responseSegmentID = responseSegmentID
  }

  package mutating func prepareResponseEntry() {
    responseEntryID = UUID().uuidString
    responseSegmentID = UUID().uuidString
  }
}

/// Stores provider-native continuation state without interpreting or rebuilding it from transcript entries.
package struct ProviderContinuationStore: Sendable, Equatable {
  private var continuationsByTurnID: [String: ProviderContinuation]
  private var latestTurnID: String?

  package init(
    continuationsByTurnID: [String: ProviderContinuation] = [:],
    latestTurnID: String? = nil,
  ) {
    self.continuationsByTurnID = continuationsByTurnID
    self.latestTurnID = latestTurnID
  }

  /// The most recently recorded continuation, if any.
  package var latest: ProviderContinuation? {
    guard let latestTurnID else { return nil }
    return continuationsByTurnID[latestTurnID]
  }

  /// Records opaque provider state for later continuation turns.
  package mutating func record(_ continuation: ProviderContinuation?) {
    guard let continuation else { return }
    continuationsByTurnID[continuation.turnID] = continuation
    latestTurnID = continuation.turnID
  }

  /// Returns an explicit continuation when supplied, otherwise the latest stored provider-native state.
  package func continuation(preferred explicitContinuation: ProviderContinuation?) -> ProviderContinuation? {
    explicitContinuation ?? latest
  }

  /// Returns stored provider-native state for a specific provider turn.
  package func continuation(forTurnID turnID: String) -> ProviderContinuation? {
    continuationsByTurnID[turnID]
  }
}

/// Accumulates token usage across turns.
package struct TokenUsageAccumulator: Sendable, Equatable {
  package private(set) var usage: TokenUsage?

  package init(usage: TokenUsage? = nil) {
    self.usage = usage
  }

  package mutating func record(_ newUsage: TokenUsage?) {
    guard let newUsage else { return }
    if usage == nil {
      usage = newUsage
    } else {
      usage?.merge(newUsage)
    }
  }
}

/// Accumulates provider response metadata, preferring newer non-empty values.
package struct ResponseMetadataAccumulator: Sendable, Equatable {
  package private(set) var metadata: ResponseMetadata?

  package init(metadata: ResponseMetadata? = nil) {
    self.metadata = metadata
  }

  package mutating func record(_ newMetadata: ResponseMetadata?) {
    guard let newMetadata else { return }
    metadata = metadata?.merging(newMetadata) ?? newMetadata
  }
}

/// Converts prompts, transcript entries, tools, and continuation state into a provider-neutral turn request.
package struct ModelRequestBuilder: Sendable {
  package var instructions: Instructions?

  package init(instructions: Instructions? = nil) {
    self.instructions = instructions
  }

  package func makeRequest(
    transcript: Transcript,
    tools: [any Tool],
    toolChoice: ToolChoice?,
    activeToolNames: Set<String>?,
    structuredOutput: StructuredOutputRequest?,
    options: GenerationOptions,
    continuation: ProviderContinuation?,
  ) -> ModelRequest {
    let filteredTools = tools.filter { tool in
      activeToolNames?.contains(tool.name) ?? true
    }
    let definitions = filteredTools.map { SwiftAgent.ToolDefinition(tool: $0) }

    return ModelRequest(
      messages: messages(from: transcript, structuredOutput: structuredOutput),
      instructions: instructions,
      tools: definitions,
      toolChoice: toolChoice,
      structuredOutput: structuredOutput,
      generationOptions: options,
      continuation: continuation,
      attachments: attachments(from: transcript),
    )
  }

  private func messages(
    from transcript: Transcript,
    structuredOutput: StructuredOutputRequest?,
  ) -> [ModelMessage] {
    let latestPromptID = transcript.entries.reversed().compactMap { entry -> String? in
      guard case let .prompt(prompt) = entry else { return nil }
      return prompt.id
    }.first

    return transcript.entries.compactMap { entry in
      switch entry {
      case let .prompt(prompt):
        ModelMessage(
          role: .user,
          segments: promptSegments(
            from: prompt,
            structuredOutput: prompt.id == latestPromptID ? structuredOutput : nil,
          ),
        )
      case let .response(response):
        ModelMessage(role: .assistant, segments: response.segments)
      case let .toolCalls(toolCalls):
        ModelMessage(
          role: .assistant,
          segments: [],
          providerMetadata: ["tool_calls": toolCallsMetadata(toolCalls.calls)],
        )
      case let .toolOutput(output):
        ModelMessage(
          role: .tool,
          segments: [output.segment],
          providerMetadata: [
            "call_id": .string(output.callId),
            "tool_name": .string(output.toolName),
          ],
        )
      case .instructions, .reasoning:
        nil
      }
    }
  }

  private func promptSegments(
    from prompt: Transcript.Prompt,
    structuredOutput: StructuredOutputRequest?,
  ) -> [Transcript.Segment] {
    guard structuredOutput?.includeSchemaInPrompt == true else {
      return prompt.segments
    }
    guard let schemaPrompt = schemaPrompt(for: structuredOutput?.format) else {
      return prompt.segments
    }

    var segments = prompt.segments
    segments.append(.text(.init(content: schemaPrompt)))
    return segments
  }

  private func schemaPrompt(for responseFormat: ResponseFormat?) -> String? {
    guard let responseFormat else { return nil }

    let typeName: String?
    let schema: GenerationSchema
    switch responseFormat {
    case .text:
      return nil
    case let .jsonSchema(name, generationSchema, _):
      typeName = name
      schema = generationSchema
    case let .generatedContent(name, generationSchema, _):
      typeName = name
      schema = generationSchema
    }

    let schemaText: String
    if let data = try? JSONEncoder().encode(schema),
       let encoded = String(data: data, encoding: .utf8) {
      schemaText = encoded
    } else {
      schemaText = String(describing: schema)
    }

    if let typeName, typeName.isEmpty == false {
      return "Respond with JSON for \(typeName) matching this schema: \(schemaText)"
    }
    return "Respond with JSON matching this schema: \(schemaText)"
  }

  private func attachments(from transcript: Transcript) -> [ModelAttachment] {
    transcript.entries.flatMap { entry -> [ModelAttachment] in
      guard case let .prompt(prompt) = entry else { return [] }
      return prompt.segments.compactMap { segment in
        guard case let .image(image) = segment else { return nil }
        return switch image.source {
        case let .data(data, mimeType):
          ModelAttachment(id: image.id, kind: .image, mimeType: mimeType, data: data)
        case let .url(url):
          ModelAttachment(id: image.id, kind: .image, url: url)
        }
      }
    }
  }

  private func toolCallsMetadata(_ calls: [Transcript.ToolCall]) -> JSONValue {
    .array(calls.map { call in
      .object([
        "id": .string(call.id),
        "call_id": .string(call.callId),
        "tool_name": .string(call.toolName),
        "arguments": .string(call.arguments.jsonString),
        "partial_arguments": call.partialArguments.map(JSONValue.string) ?? .null,
        "status": call.status.map { .string(String(describing: $0)) } ?? .null,
      ])
    })
  }
}

/// Records public transcript entries and response state.
package struct TranscriptRecorder: Sendable {
  package init() {}

  package func initialTranscript(instructions: Instructions?, tools: [any Tool]) -> Transcript {
    guard let instructions else {
      return Transcript()
    }

    let toolDefinitions = tools
      .filter(\.includesSchemaInInstructions)
      .map { Transcript.ToolDefinition(tool: $0) }
    let entry = Transcript.Entry.instructions(.init(
      segments: [.text(.init(content: instructions.description))],
      toolDefinitions: toolDefinitions,
    ))

    return Transcript(entries: [entry])
  }

  package func promptEntry(for prompt: Prompt, images: [Transcript.ImageSegment] = []) -> Transcript.Prompt {
    Transcript.Prompt(
      input: prompt.description,
      sources: Data(),
      prompt: prompt.description,
      segments: promptSegments(text: prompt.description, images: images),
    )
  }

  package func promptSegments(text: String, images: [Transcript.ImageSegment]) -> [Transcript.Segment] {
    var segments: [Transcript.Segment] = []
    if text.isEmpty == false {
      segments.append(.text(.init(content: text)))
    }
    segments.append(contentsOf: images.map(Transcript.Segment.image))
    return segments
  }

  package func appendPrompt(_ prompt: Transcript.Prompt, to state: inout ConversationState) {
    state.prepareResponseEntry()
    state.transcript.entries.append(.prompt(prompt))
  }

  package func recordEntries(_ entries: [Transcript.Entry], to state: inout ConversationState) {
    for entry in entries {
      state.transcript.upsert(entry)
    }
  }

  package func recordResponse(
    rawContent: GeneratedContent,
    status: Transcript.Status,
    to state: inout ConversationState,
  ) {
    let segment: Transcript.Segment
    if case let .string(text) = rawContent.kind {
      segment = .text(.init(id: state.responseSegmentID, content: text))
    } else {
      segment = .structure(.init(id: state.responseSegmentID, content: rawContent))
    }

    let entry = Transcript.Entry.response(.init(
      id: state.responseEntryID,
      segments: [segment],
      status: status,
    ))
    state.transcript.upsert(entry)
  }
}

/// Tracks streamed text and structured content as neutral provider events arrive.
package struct StructuredOutputAccumulator: Sendable, Equatable {
  private var textByID: [String: String] = [:]
  private var textOrder: [String] = []
  private var structuredByID: [String: GeneratedContent] = [:]

  package private(set) var currentRawContent: GeneratedContent?

  package init() {}

  package mutating func startText(id: String) {
    if textByID[id] == nil {
      textByID[id] = ""
      textOrder.append(id)
    }
    currentRawContent = GeneratedContent(text)
  }

  package mutating func appendText(id: String, delta: String) -> GeneratedContent {
    if textByID[id] == nil {
      textByID[id] = ""
      textOrder.append(id)
    }
    textByID[id, default: ""] += delta
    let rawContent = GeneratedContent(text)
    currentRawContent = rawContent
    return rawContent
  }

  package mutating func recordStructuredDelta(id: String, delta: GeneratedContent) -> GeneratedContent {
    structuredByID[id] = delta
    currentRawContent = delta
    return delta
  }

  package var text: String {
    textOrder.map { textByID[$0] ?? "" }.joined()
  }
}

/// Result of reducing one provider stream event.
package struct ModelEventReduction: Sendable, Equatable {
  package var transcriptEntries: [Transcript.Entry]
  package var rawContent: GeneratedContent?
  package var responseStatus: Transcript.Status?
  package var tokenUsage: TokenUsage?
  package var responseMetadata: ResponseMetadata?
  package var continuation: ProviderContinuation?
  package var completion: ModelTurnCompletion?
  package var warnings: [ModelWarning]

  package init(
    transcriptEntries: [Transcript.Entry] = [],
    rawContent: GeneratedContent? = nil,
    responseStatus: Transcript.Status? = nil,
    tokenUsage: TokenUsage? = nil,
    responseMetadata: ResponseMetadata? = nil,
    continuation: ProviderContinuation? = nil,
    completion: ModelTurnCompletion? = nil,
    warnings: [ModelWarning] = [],
  ) {
    self.transcriptEntries = transcriptEntries
    self.rawContent = rawContent
    self.responseStatus = responseStatus
    self.tokenUsage = tokenUsage
    self.responseMetadata = responseMetadata
    self.continuation = continuation
    self.completion = completion
    self.warnings = warnings
  }
}

/// Reduces provider-neutral model stream events into transcript, usage, metadata, and continuation updates.
package struct ModelEventReducer: Sendable {
  private var content = StructuredOutputAccumulator()
  private var reasoningTextByID: [String: String] = [:]
  private var toolCallsByLogicalID: [String: Transcript.ToolCall] = [:]
  private var toolCallOrder: [String] = []
  private var toolArgumentBuffers: [String: String] = [:]
  private var toolLogicalIDByInputID: [String: String] = [:]
  private var toolCallsEntryID: String?

  package init() {}

  package mutating func reduce(_ event: ModelStreamEvent) throws -> ModelEventReduction {
    switch event {
    case let .started(metadata):
      return ModelEventReduction(responseMetadata: metadata)

    case let .warnings(warnings):
      return ModelEventReduction(responseMetadata: ResponseMetadata(warnings: warnings), warnings: warnings)

    case let .textStarted(id, metadata):
      content.startText(id: id)
      return ModelEventReduction(responseMetadata: metadata)

    case let .textDelta(id, delta):
      return ModelEventReduction(
        rawContent: content.appendText(id: id, delta: delta),
        responseStatus: .inProgress,
      )

    case let .textCompleted(_, metadata):
      return ModelEventReduction(responseMetadata: metadata)

    case let .structuredDelta(id, delta):
      return ModelEventReduction(
        rawContent: content.recordStructuredDelta(id: id, delta: delta),
        responseStatus: .inProgress,
      )

    case let .reasoningStarted(id, metadata):
      reasoningTextByID[id] = reasoningTextByID[id] ?? ""
      return ModelEventReduction(responseMetadata: metadata)

    case let .reasoningDelta(id, delta):
      reasoningTextByID[id, default: ""] += delta
      return ModelEventReduction()

    case let .reasoningCompleted(reasoning):
      return ModelEventReduction(transcriptEntries: [.reasoning(reasoning)])

    case let .toolInputStarted(start):
      let logicalID = toolLogicalID(id: start.id, callId: start.callId)
      toolLogicalIDByInputID[start.id] = logicalID
      if toolCallsByLogicalID[logicalID] == nil {
        toolCallOrder.append(logicalID)
      }
      toolArgumentBuffers[start.id] = ""
      toolCallsByLogicalID[logicalID] = Transcript.ToolCall(
        id: start.id,
        callId: start.callId ?? start.id,
        toolName: start.toolName,
        arguments: GeneratedContent(properties: [:]),
        partialArguments: "",
        status: .inProgress,
      )
      return ModelEventReduction(transcriptEntries: [currentToolCallsEntry()])

    case let .toolInputDelta(id, delta):
      toolArgumentBuffers[id, default: ""] += delta
      guard let logicalID = toolLogicalIDByInputID[id] else {
        return ModelEventReduction()
      }
      if var call = toolCallsByLogicalID[logicalID] {
        call.partialArguments = toolArgumentBuffers[id]
        call.status = .inProgress
        toolCallsByLogicalID[logicalID] = call
      }
      return toolCallsByLogicalID[logicalID] == nil
        ? ModelEventReduction()
        : ModelEventReduction(transcriptEntries: [currentToolCallsEntry()])

    case let .toolInputCompleted(id):
      let arguments = try GeneratedContent(json: toolArgumentBuffers[id] ?? "{}")
      guard let logicalID = toolLogicalIDByInputID[id] else {
        return ModelEventReduction()
      }
      if var call = toolCallsByLogicalID[logicalID] {
        call.arguments = arguments
        call.partialArguments = nil
        call.status = .completed
        toolCallsByLogicalID[logicalID] = call
      }
      return toolCallsByLogicalID[logicalID] == nil
        ? ModelEventReduction()
        : ModelEventReduction(transcriptEntries: [currentToolCallsEntry()])

    case let .toolCallPartial(partial):
      let call = Transcript.ToolCall(
        id: partial.id,
        callId: partial.callId ?? partial.id,
        toolName: partial.toolName ?? "",
        arguments: partial.arguments ?? GeneratedContent(partial.partialArguments),
        partialArguments: partial.partialArguments,
        status: .inProgress,
      )
      recordToolCall(call)
      return ModelEventReduction(transcriptEntries: [currentToolCallsEntry()])

    case let .toolCallsCompleted(toolCalls, continuation):
      let calls = toolCalls.map(\.call)
      for call in calls {
        recordToolCall(call)
      }
      return ModelEventReduction(
        transcriptEntries: calls.isEmpty ? [] : [currentToolCallsEntry()],
        continuation: continuation,
      )

    case let .providerToolResult(output):
      return ModelEventReduction(transcriptEntries: [.toolOutput(output)])

    case let .usage(usage):
      return ModelEventReduction(tokenUsage: usage)

    case let .metadata(metadata):
      return ModelEventReduction(responseMetadata: metadata)

    case let .completed(completion):
      return ModelEventReduction(
        rawContent: content.currentRawContent,
        responseStatus: .completed,
        continuation: completion.continuation,
        completion: completion,
      )

    case let .failed(error):
      throw error

    case .source, .file, .raw:
      return ModelEventReduction()
    }
  }

  private mutating func recordToolCall(_ call: Transcript.ToolCall) {
    let logicalID = toolLogicalID(id: call.id, callId: call.callId)
    if toolCallsByLogicalID[logicalID] == nil {
      toolCallOrder.append(logicalID)
    }
    toolCallsByLogicalID[logicalID] = call
  }

  private func toolLogicalID(id: String, callId: String?) -> String {
    callId ?? id
  }

  private mutating func currentToolCallsEntry() -> Transcript.Entry {
    if toolCallsEntryID == nil {
      toolCallsEntryID = "tool-calls-\(toolCallOrder.first ?? UUID().uuidString)"
    }
    let calls = toolCallOrder.compactMap { toolCallsByLogicalID[$0] }
    return .toolCalls(.init(id: toolCallsEntryID!, calls: calls))
  }
}

/// A transcript-derived snapshot emitted while the shared engine reduces a model stream.
package struct ConversationStreamSnapshot: Sendable, Equatable {
  package var modelEvent: ModelStreamEvent?
  package var transcript: Transcript
  package var rawContent: GeneratedContent?
  package var transcriptEntries: [Transcript.Entry]
  package var tokenUsage: TokenUsage?
  package var responseMetadata: ResponseMetadata?
  package var completion: ModelTurnCompletion?
  package var continuation: ProviderContinuation?

  package init(
    modelEvent: ModelStreamEvent? = nil,
    transcript: Transcript,
    rawContent: GeneratedContent? = nil,
    transcriptEntries: [Transcript.Entry] = [],
    tokenUsage: TokenUsage? = nil,
    responseMetadata: ResponseMetadata? = nil,
    completion: ModelTurnCompletion? = nil,
    continuation: ProviderContinuation? = nil,
  ) {
    self.modelEvent = modelEvent
    self.transcript = transcript
    self.rawContent = rawContent
    self.transcriptEntries = transcriptEntries
    self.tokenUsage = tokenUsage
    self.responseMetadata = responseMetadata
    self.completion = completion
    self.continuation = continuation
  }
}

/// Shared model conversation engine used by future public sessions.
package actor ConversationEngine {
  private let model: any LanguageModel
  private let tools: [any Tool]
  private var state: ConversationState
  private let recorder = TranscriptRecorder()
  private let requestBuilder: ModelRequestBuilder

  package var transcript: Transcript {
    state.transcript
  }

  package var tokenUsage: TokenUsage? {
    state.tokenUsage
  }

  package var responseMetadata: ResponseMetadata? {
    state.responseMetadata
  }

  package var latestContinuation: ProviderContinuation? {
    state.continuationStore.latest
  }

  package init(
    model: any LanguageModel,
    instructions: Instructions? = nil,
    tools: [any Tool] = [],
  ) {
    self.model = model
    self.tools = tools
    requestBuilder = ModelRequestBuilder(instructions: instructions)
    state = ConversationState(transcript: recorder.initialTranscript(instructions: instructions, tools: tools))
  }

  /// Builds a provider-neutral request, optionally appending a prompt entry to the public transcript first.
  package func makeRequest(
    prompt: Prompt? = nil,
    promptEntry: Transcript.Prompt? = nil,
    toolChoice: ToolChoice? = nil,
    activeToolNames: Set<String>? = nil,
    structuredOutput: StructuredOutputRequest? = nil,
    options: GenerationOptions = GenerationOptions(),
    continuation explicitContinuation: ProviderContinuation? = nil,
  ) -> ModelRequest {
    if let promptEntry {
      recorder.appendPrompt(promptEntry, to: &state)
    } else if let prompt {
      recorder.appendPrompt(recorder.promptEntry(for: prompt), to: &state)
    }

    return requestBuilder.makeRequest(
      transcript: state.transcript,
      tools: tools,
      toolChoice: toolChoice,
      activeToolNames: activeToolNames,
      structuredOutput: structuredOutput,
      options: options,
      continuation: state.continuationStore.continuation(preferred: explicitContinuation),
    )
  }

  /// Runs one non-streaming model turn and records the result into shared state.
  @discardableResult
  package func respond(
    prompt: Prompt? = nil,
    promptEntry: Transcript.Prompt? = nil,
    toolChoice: ToolChoice? = nil,
    activeToolNames: Set<String>? = nil,
    structuredOutput: StructuredOutputRequest? = nil,
    options: GenerationOptions = GenerationOptions(),
    continuation: ProviderContinuation? = nil,
  ) async throws -> ModelResponse {
    let request = makeRequest(
      prompt: prompt,
      promptEntry: promptEntry,
      toolChoice: toolChoice,
      activeToolNames: activeToolNames,
      structuredOutput: structuredOutput,
      options: options,
      continuation: continuation,
    )
    let response = try await model.respond(to: request)
    apply(response)
    return response
  }

  /// Streams one model turn and records each reduced update into shared state.
  package func streamResponse(
    prompt: Prompt? = nil,
    promptEntry: Transcript.Prompt? = nil,
    toolChoice: ToolChoice? = nil,
    activeToolNames: Set<String>? = nil,
    structuredOutput: StructuredOutputRequest? = nil,
    options: GenerationOptions = GenerationOptions(),
    continuation: ProviderContinuation? = nil,
  ) -> AsyncThrowingStream<ConversationStreamSnapshot, any Error> {
    let request = makeRequest(
      prompt: prompt,
      promptEntry: promptEntry,
      toolChoice: toolChoice,
      activeToolNames: activeToolNames,
      structuredOutput: structuredOutput,
      options: options,
      continuation: continuation,
    )
    let upstream = model.streamResponse(to: request)

    return relayStream(upstream: upstream)
  }

  private nonisolated func relayStream(
    upstream: AsyncThrowingStream<ModelStreamEvent, any Error>,
  ) -> AsyncThrowingStream<ConversationStreamSnapshot, any Error> {
    return AsyncThrowingStream { continuation in
      let task = Task {
        var reducer = ModelEventReducer()
        do {
          for try await event in upstream {
            try Task.checkCancellation()
            let reduction = try reducer.reduce(event)
            try Task.checkCancellation()
            let snapshot = await self.apply(reduction, event: event)
            try Task.checkCancellation()
            if case .terminated = continuation.yield(snapshot) {
              return
            }
          }
          continuation.finish()
        } catch is CancellationError {
          return
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Applies a complete model response to transcript, usage, metadata, and continuation state.
  package func apply(_ response: ModelResponse) {
    recorder.recordEntries(response.transcriptEntries, to: &state)
    recorder.recordEntries(response.reasoning.map(Transcript.Entry.reasoning), to: &state)
    if response.toolCalls.isEmpty == false {
      recorder.recordEntries([.toolCalls(.init(calls: response.toolCalls.map(\.call)))], to: &state)
    }
    if let content = response.content {
      recorder.recordResponse(rawContent: content, status: .completed, to: &state)
    }
    record(usage: response.tokenUsage, metadata: response.responseMetadata, continuation: response.continuation, in: &state)
  }

  @discardableResult
  private func apply(_ reduction: ModelEventReduction, event: ModelStreamEvent? = nil) -> ConversationStreamSnapshot {
    recorder.recordEntries(reduction.transcriptEntries, to: &state)
    if let rawContent = reduction.rawContent, let status = reduction.responseStatus {
      recorder.recordResponse(rawContent: rawContent, status: status, to: &state)
    }
    record(
      usage: reduction.tokenUsage,
      metadata: reduction.responseMetadata,
      continuation: reduction.continuation,
      in: &state,
    )
    return ConversationStreamSnapshot(
      modelEvent: event,
      transcript: state.transcript,
      rawContent: reduction.rawContent,
      transcriptEntries: reduction.transcriptEntries,
      tokenUsage: state.tokenUsage,
      responseMetadata: state.responseMetadata,
      completion: reduction.completion,
      continuation: reduction.continuation,
    )
  }

  private func record(
    usage: TokenUsage?,
    metadata: ResponseMetadata?,
    continuation: ProviderContinuation?,
    in state: inout ConversationState,
  ) {
    var usageAccumulator = TokenUsageAccumulator(usage: state.tokenUsage)
    usageAccumulator.record(usage)
    state.tokenUsage = usageAccumulator.usage

    var metadataAccumulator = ResponseMetadataAccumulator(metadata: state.responseMetadata)
    metadataAccumulator.record(metadata)
    state.responseMetadata = metadataAccumulator.metadata

    state.continuationStore.record(continuation)
  }
}
