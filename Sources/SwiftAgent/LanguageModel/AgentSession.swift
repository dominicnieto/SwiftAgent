import Foundation
import Observation

/// Configuration for a single-agent runtime.
public struct AgentConfiguration: Sendable, Equatable {
  /// Maximum model turns allowed for one run.
  public var maxIterations: Int

  /// Policy used when executing local SwiftAgent tools.
  public var toolExecutionPolicy: ToolExecutionPolicy

  /// Whether a tool execution error should stop the run.
  public var stopOnToolError: Bool

  /// Creates an agent configuration.
  public init(
    maxIterations: Int = 8,
    toolExecutionPolicy: ToolExecutionPolicy = .automatic,
    stopOnToolError: Bool = true,
  ) {
    self.maxIterations = max(1, maxIterations)
    self.toolExecutionPolicy = toolExecutionPolicy
    self.stopOnToolError = stopOnToolError
  }
}

/// Result for one model/tool iteration.
public struct AgentStepResult: Sendable, Equatable {
  /// One-based iteration number.
  public var index: Int

  /// Transcript entries produced during this iteration.
  public var transcriptEntries: [Transcript.Entry]

  /// Local tool calls executed after the model response.
  public var toolCalls: [Transcript.ToolCall]

  /// Tool outputs produced for the calls.
  public var toolOutputs: [Transcript.ToolOutput]

  /// Token usage state after this iteration.
  public var tokenUsage: TokenUsage?

  /// Provider metadata state after this iteration.
  public var responseMetadata: ResponseMetadata?

  /// Provider finish reason for this iteration.
  public var finishReason: FinishReason

  /// Creates a step result.
  public init(
    index: Int,
    transcriptEntries: [Transcript.Entry] = [],
    toolCalls: [Transcript.ToolCall] = [],
    toolOutputs: [Transcript.ToolOutput] = [],
    tokenUsage: TokenUsage? = nil,
    responseMetadata: ResponseMetadata? = nil,
    finishReason: FinishReason = .completed,
  ) {
    self.index = index
    self.transcriptEntries = transcriptEntries
    self.toolCalls = toolCalls
    self.toolOutputs = toolOutputs
    self.tokenUsage = tokenUsage
    self.responseMetadata = responseMetadata
    self.finishReason = finishReason
  }
}

/// Complete result from an agent run.
public struct AgentResult<Content>: Sendable where Content: Generable & Sendable {
  /// Decoded final answer.
  public var content: Content

  /// Raw final generated content.
  public var rawContent: GeneratedContent

  /// Full transcript after the run.
  public var transcript: Transcript

  /// Aggregated token usage for the run.
  public var tokenUsage: TokenUsage?

  /// Latest response metadata.
  public var responseMetadata: ResponseMetadata?

  /// Per-iteration model/tool history.
  public var steps: [AgentStepResult]

  /// Tool calls produced across the run.
  public var toolCalls: [Transcript.ToolCall]

  /// Tool outputs produced across the run.
  public var toolOutputs: [Transcript.ToolOutput]

  /// Number of model/tool iterations performed.
  public var iterationCount: Int

  /// Creates an agent result.
  public init(
    content: Content,
    rawContent: GeneratedContent,
    transcript: Transcript,
    steps: [AgentStepResult] = [],
    toolCalls: [Transcript.ToolCall] = [],
    toolOutputs: [Transcript.ToolOutput] = [],
    tokenUsage: TokenUsage? = nil,
    responseMetadata: ResponseMetadata? = nil,
    iterationCount: Int? = nil,
  ) {
    self.content = content
    self.rawContent = rawContent
    self.transcript = transcript
    self.steps = steps
    self.toolCalls = toolCalls
    self.toolOutputs = toolOutputs
    self.tokenUsage = tokenUsage
    self.responseMetadata = responseMetadata
    self.iterationCount = iterationCount ?? steps.count
  }
}

/// Streaming events emitted by ``AgentSession``.
public enum AgentEvent<Content>: Sendable where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
  case started
  case iterationStarted(Int)
  case modelEvent(ModelStreamEvent)
  case partialContent(Content.PartiallyGenerated)
  case toolInputStarted(Transcript.ToolCall)
  case toolInputDelta(id: String, delta: String)
  case toolInputCompleted(Transcript.ToolCall)
  case toolCallStarted(Transcript.ToolCall)
  case toolApprovalRequested(Transcript.ToolCall)
  case toolExecutionStarted(Transcript.ToolCall)
  case toolOutputDelta(Transcript.ToolOutput)
  case toolCallCompleted(Transcript.ToolCall)
  case toolOutput(Transcript.ToolOutput)
  case toolExecutionFailed(Transcript.ToolCall, any Error)
  case iterationCompleted(AgentStepResult)
  case completed(AgentResult<Content>)
  case failed(any Error)
}

/// A single-agent runtime that owns local tool execution and model continuation loops.
@Observable
public final class AgentSession: @unchecked Sendable {
  @ObservationIgnored private let modelSession: LanguageModelSession
  @ObservationIgnored private let state: Locked<AgentState>
  @ObservationIgnored private let toolExecutionDelegateStorage = Locked<(any ToolExecutionDelegate)?>(nil)

  /// Tools available to the agent.
  public let tools: [any Tool]

  /// Provider-defined tools serialized by the provider and executed remotely.
  public let providerTools: [ToolDefinition]

  /// Instructions applied to each model turn.
  public let instructions: Instructions?

  /// Agent runtime configuration.
  public let configuration: AgentConfiguration

  /// Delegate that can approve, stop, or provide output for tool calls.
  public var toolExecutionDelegate: (any ToolExecutionDelegate)? {
    get { toolExecutionDelegateStorage.withLock { $0 } }
    set { toolExecutionDelegateStorage.withLock { $0 = newValue } }
  }

  /// Whether this agent is currently running.
  public var isRunning: Bool {
    access(keyPath: \.isRunning)
    return state.withLock { $0.isRunning }
  }

  /// Current public transcript.
  public var transcript: Transcript {
    access(keyPath: \.transcript)
    return state.withLock { $0.transcript }
  }

  /// Aggregated token usage.
  public var tokenUsage: TokenUsage? {
    access(keyPath: \.tokenUsage)
    return state.withLock { $0.tokenUsage }
  }

  /// Latest response metadata.
  public var responseMetadata: ResponseMetadata? {
    access(keyPath: \.responseMetadata)
    return state.withLock { $0.responseMetadata }
  }

  /// Current one-based iteration, or zero when idle.
  public var currentIteration: Int {
    access(keyPath: \.currentIteration)
    return state.withLock { $0.currentIteration }
  }

  /// Current tool calls being executed.
  public var currentToolCalls: [Transcript.ToolCall] {
    access(keyPath: \.currentToolCalls)
    return state.withLock { $0.currentToolCalls }
  }

  /// Current tool outputs produced in the active iteration.
  public var currentToolOutputs: [Transcript.ToolOutput] {
    access(keyPath: \.currentToolOutputs)
    return state.withLock { $0.currentToolOutputs }
  }

  /// Latest error observed by the agent.
  public var latestError: (any Error)? {
    access(keyPath: \.latestError)
    return state.withLock { $0.latestError }
  }

  /// Creates an agent session.
  public init(
    model: any LanguageModel,
    tools: [any Tool] = [],
    providerTools: [ToolDefinition] = [],
    instructions: Instructions? = nil,
    configuration: AgentConfiguration = AgentConfiguration(),
  ) {
    self.tools = tools
    self.providerTools = providerTools
    self.instructions = instructions
    self.configuration = configuration
    modelSession = LanguageModelSession(model: model, tools: tools, providerTools: providerTools, instructions: instructions)
    state = Locked(AgentState(transcript: TranscriptRecorder().initialTranscript(instructions: instructions, tools: tools)))
  }

  /// Creates an agent session with string instructions.
  public convenience init(
    model: any LanguageModel,
    tools: [any Tool] = [],
    providerTools: [ToolDefinition] = [],
    instructions: String,
    configuration: AgentConfiguration = AgentConfiguration(),
  ) {
    self.init(
      model: model,
      tools: tools,
      providerTools: providerTools,
      instructions: Instructions(instructions),
      configuration: configuration,
    )
  }

  /// Creates an agent session with tools declared by a session schema.
  public convenience init<SessionSchema>(
    model: any LanguageModel,
    schema: SessionSchema,
    providerTools: [ToolDefinition] = [],
    instructions: Instructions? = nil,
    configuration: AgentConfiguration = AgentConfiguration(),
  ) where SessionSchema: TranscriptSchema {
    self.init(model: model, tools: schema.tools, providerTools: providerTools, instructions: instructions, configuration: configuration)
  }

  /// Creates an agent session with schema-declared tools and string instructions.
  public convenience init<SessionSchema>(
    model: any LanguageModel,
    schema: SessionSchema,
    providerTools: [ToolDefinition] = [],
    instructions: String,
    configuration: AgentConfiguration = AgentConfiguration(),
  ) where SessionSchema: TranscriptSchema {
    self.init(
      model: model,
      schema: schema,
      providerTools: providerTools,
      instructions: Instructions(instructions),
      configuration: configuration,
    )
  }

  /// Runs the agent until it produces a final answer or hits a stop condition.
  @discardableResult
  public func run<Content>(
    to prompt: Prompt,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> AgentResult<Content> where Content: Generable & Sendable {
    try await run(
      prompt: prompt,
      promptEntry: Self.promptEntry(for: prompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  private func run<Content>(
    prompt: Prompt,
    promptEntry: Transcript.Prompt,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> AgentResult<Content> where Content: Generable & Sendable {
    beginRunning()
    defer { endRunning() }

    let structuredOutput = structuredOutputRequest(for: type, includeSchemaInPrompt: includeSchemaInPrompt)
    var steps: [AgentStepResult] = []
    var response: ModelResponse?
    var pendingToolOutputs: [Transcript.ToolOutput] = []

    do {
      for iteration in 1 ... configuration.maxIterations {
        setCurrentIteration(iteration)
        let turnResponse = try await modelSession.modelResponseForRuntime(
          promptEntry: iteration == 1 ? promptEntry : nil,
          toolOutputs: pendingToolOutputs,
          structuredOutput: structuredOutput,
          options: options,
        )
        pendingToolOutputs = []
        response = turnResponse
        syncFromModelSession()

        let localToolCalls = turnResponse.toolCalls
          .filter { $0.kind == .local }
          .map(\.call)

        guard localToolCalls.isEmpty == false else {
          steps.append(await stepResult(
            index: iteration,
            response: turnResponse,
          ))
          break
        }

        let execution = try await executeToolCalls(localToolCalls, recordTranscript: false)
        let outputs: [Transcript.ToolOutput]
        switch execution {
        case .stop(let calls):
          steps.append(await stepResult(
            index: iteration,
            response: turnResponse,
            toolCalls: calls,
          ))
          return try await result(
            from: turnResponse.content ?? GeneratedContent(""),
            as: type,
            steps: steps,
          )
        case .outputs(let results):
          outputs = results.map(\.output)
        }

        pendingToolOutputs = outputs

        steps.append(await stepResult(
          index: iteration,
          response: turnResponse,
          toolCalls: localToolCalls,
          toolOutputs: outputs,
        ))

        if AgentStopPolicy(maxIterations: configuration.maxIterations).shouldStop(after: iteration) {
          throw AgentSessionError.maxIterationsExceeded(configuration.maxIterations)
        }
      }

      guard let rawContent = response?.content else {
        throw AgentSessionError.noFinalResponse
      }
      return try await result(from: rawContent, as: type, steps: steps)
    } catch {
      setLatestError(error)
      throw error
    }
  }

  /// Runs a string-producing agent task.
  @discardableResult
  public func run(
    to prompt: Prompt,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> AgentResult<String> {
    try await run(to: prompt, generating: String.self, includeSchemaInPrompt: true, options: options)
  }

  /// Runs a string-producing agent task from a plain prompt.
  @discardableResult
  public func run(
    to prompt: String,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> AgentResult<String> {
    try await run(to: Prompt(prompt), options: options)
  }

  /// Runs a structured-output agent task from a plain prompt.
  @discardableResult
  public func run<Content>(
    to prompt: String,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> AgentResult<Content> where Content: Generable & Sendable {
    try await run(
      to: Prompt(prompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Streams a string-producing agent run, including model and tool lifecycle events.
  public func stream(
    to prompt: Prompt,
    options: GenerationOptions = GenerationOptions(),
  ) -> AsyncThrowingStream<AgentEvent<String>, any Error> {
    stream(to: prompt, generating: String.self, includeSchemaInPrompt: true, options: options)
  }

  /// Streams a string-producing agent run from a plain prompt.
  public func stream(
    to prompt: String,
    options: GenerationOptions = GenerationOptions(),
  ) -> AsyncThrowingStream<AgentEvent<String>, any Error> {
    stream(to: Prompt(prompt), options: options)
  }

  /// Streams an agent run with typed partial content and a typed final result.
  public func stream<Content>(
    to prompt: Prompt,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) -> AsyncThrowingStream<AgentEvent<Content>, any Error>
    where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    stream(
      prompt: prompt,
      promptEntry: Self.promptEntry(for: prompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Streams a structured-output agent run from a plain prompt.
  public func stream<Content>(
    to prompt: String,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) -> AsyncThrowingStream<AgentEvent<Content>, any Error>
    where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    stream(
      to: Prompt(prompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  private func stream<Content>(
    prompt: Prompt,
    promptEntry: Transcript.Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) -> AsyncThrowingStream<AgentEvent<Content>, any Error>
    where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    AsyncThrowingStream { continuation in
      let task = Task {
        beginRunning()
        defer { endRunning() }

        do {
          continuation.yield(.started)
          let structuredOutput = structuredOutputRequest(for: type, includeSchemaInPrompt: includeSchemaInPrompt)
          var steps: [AgentStepResult] = []
          var latestRawContent: GeneratedContent?
          var latestToolCallsByID: [String: Transcript.ToolCall] = [:]
          var latestToolCallKindsByID: [String: ToolDefinitionKind] = [:]
          var pendingToolOutputs: [Transcript.ToolOutput] = []

          for iteration in 1 ... configuration.maxIterations {
            setCurrentIteration(iteration)
            continuation.yield(.iterationStarted(iteration))

            var completedSnapshot: ConversationStreamSnapshot?
            var iterationEntries: [Transcript.Entry] = []
            var iterationFinishReason: FinishReason = .completed
            var iterationModelToolCallsByID: [String: ModelToolCall] = [:]
            var iterationModelToolCallOrder: [String] = []

            let stream = modelSession.modelStreamForRuntime(
              promptEntry: iteration == 1 ? promptEntry : nil,
              toolOutputs: pendingToolOutputs,
              structuredOutput: structuredOutput,
              options: options,
            )
            pendingToolOutputs = []
            for try await snapshot in stream {
              completedSnapshot = snapshot
              iterationEntries.append(contentsOf: snapshot.transcriptEntries)
              latestRawContent = snapshot.rawContent ?? latestRawContent
              if let finishReason = snapshot.completion?.finishReason {
                iterationFinishReason = finishReason
              }
              syncFromModelSession()
              for entry in snapshot.transcriptEntries {
                if case let .toolCalls(toolCalls) = entry {
                  for call in toolCalls.calls {
                    latestToolCallsByID[call.id] = call
                    latestToolCallsByID[call.callId] = call
                  }
                }
              }
              if let event = snapshot.modelEvent {
                recordModelToolCalls(
                  from: event,
                  snapshot: snapshot,
                  latestToolCallsByID: latestToolCallsByID,
                  latestToolCallKindsByID: &latestToolCallKindsByID,
                  modelToolCallsByID: &iterationModelToolCallsByID,
                  modelToolCallOrder: &iterationModelToolCallOrder,
                )
                continuation.yield(.modelEvent(event))
                yieldAgentEvents(for: event, snapshot: snapshot, latestToolCallsByID: latestToolCallsByID, to: continuation)
              }
              if let rawContent = snapshot.rawContent,
                 let partial = Self.partialContent(from: rawContent, as: type) {
                continuation.yield(.partialContent(partial))
              }
            }

            let transcriptToolCalls = modelSession.transcript.entries.reversed().compactMap { entry -> [Transcript.ToolCall]? in
              guard case let .toolCalls(toolCalls) = entry else { return nil }
              return toolCalls.calls
            }.first ?? []
            let snapshotToolCalls = completedSnapshot?.transcriptEntries.compactMap { entry -> [Transcript.ToolCall]? in
              guard case let .toolCalls(toolCalls) = entry else { return nil }
              return toolCalls.calls
            }.flatMap(\.self) ?? []
            let transcriptOnlyToolCalls = snapshotToolCalls.isEmpty && completedSnapshot?.rawContent == nil
              ? transcriptToolCalls
              : snapshotToolCalls
            let modelToolCalls = iterationModelToolCallOrder.compactMap { iterationModelToolCallsByID[$0] }
            let toolCalls = modelToolCalls.isEmpty ? transcriptOnlyToolCalls : modelToolCalls.map(\.call)
            let localToolCalls = modelToolCalls.isEmpty
              ? toolCalls.filter { $0.status == .completed }
              : modelToolCalls.filter { $0.kind == .local && $0.call.status == .completed }.map(\.call)

            guard localToolCalls.isEmpty == false else {
              guard let rawContent = latestRawContent ?? completedSnapshot?.rawContent else {
                throw AgentSessionError.noFinalResponse
              }
              let step = await stepResult(
                index: iteration,
                transcriptEntries: iterationEntries,
                toolCalls: [],
                toolOutputs: [],
                finishReason: iterationFinishReason,
              )
              let completedSteps = steps + [step]
              continuation.yield(.iterationCompleted(step))
              let result = try await result(
                from: rawContent,
                as: type,
                steps: completedSteps,
              )
              continuation.yield(.completed(result))
              continuation.finish()
              return
            }

            for call in localToolCalls {
              continuation.yield(.toolCallStarted(call))
            }
            let execution = try await executeToolCalls(localToolCalls, recordTranscript: false) { event in
              continuation.yield(AgentEvent(event))
            }
            guard case let .outputs(results) = execution else {
              let step = await stepResult(
                index: iteration,
                transcriptEntries: iterationEntries,
                toolCalls: localToolCalls,
                finishReason: .toolCalls,
              )
              steps.append(step)
              continuation.yield(.iterationCompleted(step))
              let result = try await result(from: latestRawContent ?? GeneratedContent(""), as: type, steps: steps)
              continuation.yield(.completed(result))
              continuation.finish()
              return
            }

            let outputs = results.map(\.output)
            iterationEntries.append(contentsOf: outputs.map(Transcript.Entry.toolOutput))
            pendingToolOutputs = outputs

            let step = await stepResult(
              index: iteration,
              transcriptEntries: iterationEntries,
              toolCalls: localToolCalls,
              toolOutputs: outputs,
              finishReason: .toolCalls,
            )
            steps.append(step)
            continuation.yield(.iterationCompleted(step))

            if AgentStopPolicy(maxIterations: configuration.maxIterations).shouldStop(after: iteration) {
              throw AgentSessionError.maxIterationsExceeded(configuration.maxIterations)
            }
          }
        } catch {
          setLatestError(error)
          continuation.yield(.failed(error))
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

public extension AgentSession {
  /// Runs a text-producing agent task while storing typed grounding values next to the prompt transcript entry.
  @discardableResult
  func run<SessionSchema>(
    to input: String,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) async throws -> AgentResult<String> where SessionSchema: TranscriptSchema & GroundingSupportingSchema {
    let renderedPrompt = prompt(input, sources)
    return try await run(
      prompt: renderedPrompt,
      promptEntry: try Self.promptEntry(input: input, sources: sources, schema: schema, prompt: renderedPrompt),
      generating: String.self,
      options: options,
    )
  }

  /// Runs a structured-output agent task while storing typed grounding values next to the prompt transcript entry.
  @discardableResult
  func run<SessionSchema, Content>(
    to input: String,
    generating type: Content.Type,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) async throws -> AgentResult<Content>
    where SessionSchema: TranscriptSchema & GroundingSupportingSchema,
    Content: Generable & Sendable {
    let renderedPrompt = prompt(input, sources)
    return try await run(
      prompt: renderedPrompt,
      promptEntry: try Self.promptEntry(input: input, sources: sources, schema: schema, prompt: renderedPrompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Runs a structured output registered on a session schema while storing typed groundings.
  @discardableResult
  func run<SessionSchema, Output>(
    to input: String,
    generating type: KeyPath<SessionSchema.StructuredOutputs, Output.Type>,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) async throws -> AgentResult<Output.Schema>
    where SessionSchema: TranscriptSchema & GroundingSupportingSchema,
    Output: StructuredOutput,
    Output.Schema: Sendable {
    try await run(
      to: input,
      generating: Output.Schema.self,
      schema: schema,
      groundingWith: sources,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
      embeddingInto: prompt,
    )
  }

  /// Streams a text-producing agent task while storing typed grounding values next to the prompt transcript entry.
  func stream<SessionSchema>(
    to input: String,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) throws -> AsyncThrowingStream<AgentEvent<String>, any Error>
    where SessionSchema: TranscriptSchema & GroundingSupportingSchema {
    let renderedPrompt = prompt(input, sources)
    return try stream(
      prompt: renderedPrompt,
      promptEntry: Self.promptEntry(input: input, sources: sources, schema: schema, prompt: renderedPrompt),
      generating: String.self,
      includeSchemaInPrompt: true,
      options: options,
    )
  }

  /// Streams a structured-output agent task while storing typed grounding values next to the prompt transcript entry.
  func stream<SessionSchema, Content>(
    to input: String,
    generating type: Content.Type,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) throws -> AsyncThrowingStream<AgentEvent<Content>, any Error>
    where SessionSchema: TranscriptSchema & GroundingSupportingSchema,
    Content: Generable & Sendable,
    Content.PartiallyGenerated: Sendable {
    let renderedPrompt = prompt(input, sources)
    return try stream(
      prompt: renderedPrompt,
      promptEntry: Self.promptEntry(input: input, sources: sources, schema: schema, prompt: renderedPrompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Streams a structured output registered on a session schema while storing typed groundings.
  func stream<SessionSchema, Output>(
    to input: String,
    generating type: KeyPath<SessionSchema.StructuredOutputs, Output.Type>,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) throws -> AsyncThrowingStream<AgentEvent<Output.Schema>, any Error>
    where SessionSchema: TranscriptSchema & GroundingSupportingSchema,
    Output: StructuredOutput,
    Output.Schema: Sendable,
    Output.Schema.PartiallyGenerated: Sendable {
    try stream(
      to: input,
      generating: Output.Schema.self,
      schema: schema,
      groundingWith: sources,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
      embeddingInto: prompt,
    )
  }
}

public extension AgentSession {
  /// Error thrown when an agent-owned tool call cannot be completed.
  struct ToolCallError: Error, LocalizedError {
    public let toolName: String
    public let underlyingError: any Error

    public init(tool: any Tool, underlyingError: any Error) {
      toolName = tool.name
      self.underlyingError = underlyingError
    }

    public init(toolName: String, underlyingError: any Error) {
      self.toolName = toolName
      self.underlyingError = underlyingError
    }

    public var errorDescription: String? {
      "Tool '\(toolName)' failed: \(underlyingError.localizedDescription)"
    }
  }

  /// Output from an agent-owned tool call.
  struct ToolExecutionResult: Sendable, Equatable {
    public var call: Transcript.ToolCall
    public var output: Transcript.ToolOutput

    public init(call: Transcript.ToolCall, output: Transcript.ToolOutput) {
      self.call = call
      self.output = output
    }
  }

  /// Result of asking the agent to handle emitted tool calls.
  enum ToolExecutionOutcome: Sendable, Equatable {
    case stop(calls: [Transcript.ToolCall])
    case outputs([ToolExecutionResult])
  }

  /// Executes model-emitted tool calls through this agent's tool policy.
  func executeToolCalls(
    _ calls: [Transcript.ToolCall],
    recordTranscript: Bool = true,
  ) async throws -> ToolExecutionOutcome {
    try await executeToolCalls(calls, recordTranscript: recordTranscript, eventSink: nil as ((AgentToolExecutionEvent) -> Void)?)
  }
}

private enum AgentToolExecutionEvent: Sendable {
  case approvalRequested(Transcript.ToolCall)
  case executionStarted(Transcript.ToolCall)
  case outputDelta(Transcript.ToolOutput)
  case callCompleted(Transcript.ToolCall)
  case output(Transcript.ToolOutput)
  case executionFailed(Transcript.ToolCall, any Error)
}

private extension AgentEvent {
  init(_ event: AgentToolExecutionEvent) {
    switch event {
    case .approvalRequested(let call):
      self = .toolApprovalRequested(call)
    case .executionStarted(let call):
      self = .toolExecutionStarted(call)
    case .outputDelta(let output):
      self = .toolOutputDelta(output)
    case .callCompleted(let call):
      self = .toolCallCompleted(call)
    case .output(let output):
      self = .toolOutput(output)
    case .executionFailed(let call, let error):
      self = .toolExecutionFailed(call, error)
    }
  }
}

private extension AgentSession {
  func recordModelToolCalls(
    from event: ModelStreamEvent,
    snapshot: ConversationStreamSnapshot,
    latestToolCallsByID: [String: Transcript.ToolCall],
    latestToolCallKindsByID: inout [String: ToolDefinitionKind],
    modelToolCallsByID: inout [String: ModelToolCall],
    modelToolCallOrder: inout [String],
  ) {
    switch event {
    case let .toolInputStarted(start):
      let call = Transcript.ToolCall(
        id: start.id,
        callId: start.callId ?? start.id,
        toolName: start.toolName,
        arguments: GeneratedContent(properties: [:]),
        partialArguments: "",
        status: .inProgress,
      )
      recordModelToolCall(
        ModelToolCall(call: call, kind: start.kind, providerMetadata: start.providerMetadata),
        latestToolCallKindsByID: &latestToolCallKindsByID,
        modelToolCallsByID: &modelToolCallsByID,
        modelToolCallOrder: &modelToolCallOrder,
      )

    case let .toolCallPartial(partial):
      let call = Transcript.ToolCall(
        id: partial.id,
        callId: partial.callId ?? partial.id,
        toolName: partial.toolName ?? "",
        arguments: partial.arguments ?? GeneratedContent(partial.partialArguments),
        partialArguments: partial.partialArguments,
        status: .inProgress,
      )
      recordModelToolCall(
        ModelToolCall(call: call, kind: partial.kind),
        latestToolCallKindsByID: &latestToolCallKindsByID,
        modelToolCallsByID: &modelToolCallsByID,
        modelToolCallOrder: &modelToolCallOrder,
      )

    case let .toolInputCompleted(id):
      guard let call = latestToolCallsByID[id] ?? completedToolCall(withID: id, from: snapshot) else {
        return
      }
      let kind = latestToolCallKindsByID[id]
        ?? latestToolCallKindsByID[call.id]
        ?? latestToolCallKindsByID[call.callId]
        ?? .local
      recordModelToolCall(
        ModelToolCall(call: call, kind: kind),
        latestToolCallKindsByID: &latestToolCallKindsByID,
        modelToolCallsByID: &modelToolCallsByID,
        modelToolCallOrder: &modelToolCallOrder,
      )

    case let .toolCallsCompleted(toolCalls):
      for toolCall in toolCalls {
        recordModelToolCall(
          toolCall,
          latestToolCallKindsByID: &latestToolCallKindsByID,
          modelToolCallsByID: &modelToolCallsByID,
          modelToolCallOrder: &modelToolCallOrder,
        )
      }

    default:
      break
    }
  }

  func recordModelToolCall(
    _ toolCall: ModelToolCall,
    latestToolCallKindsByID: inout [String: ToolDefinitionKind],
    modelToolCallsByID: inout [String: ModelToolCall],
    modelToolCallOrder: inout [String],
  ) {
    let logicalID = toolCall.call.callId
    if modelToolCallsByID[logicalID] == nil {
      modelToolCallOrder.append(logicalID)
    }
    modelToolCallsByID[logicalID] = toolCall
    latestToolCallKindsByID[toolCall.call.id] = toolCall.kind
    latestToolCallKindsByID[toolCall.call.callId] = toolCall.kind
  }

  func yieldAgentEvents<Content>(
    for event: ModelStreamEvent,
    snapshot: ConversationStreamSnapshot,
    latestToolCallsByID: [String: Transcript.ToolCall],
    to continuation: AsyncThrowingStream<AgentEvent<Content>, any Error>.Continuation,
  ) where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    switch event {
    case let .toolInputStarted(start):
      let call = Transcript.ToolCall(
        id: start.id,
        callId: start.callId ?? start.id,
        toolName: start.toolName,
        arguments: GeneratedContent(properties: [:]),
        partialArguments: "",
        status: .inProgress,
      )
      continuation.yield(.toolInputStarted(call))

    case let .toolInputDelta(id, delta):
      continuation.yield(.toolInputDelta(id: id, delta: delta))

    case let .toolInputCompleted(id):
      let completedCall = latestToolCallsByID[id] ?? completedToolCall(withID: id, from: snapshot)
      if let completedCall {
        continuation.yield(.toolInputCompleted(completedCall))
      }

    case let .toolCallPartial(partial):
      let call = Transcript.ToolCall(
        id: partial.id,
        callId: partial.callId ?? partial.id,
        toolName: partial.toolName ?? "",
        arguments: partial.arguments ?? GeneratedContent(partial.partialArguments),
        partialArguments: partial.partialArguments,
        status: .inProgress,
      )
      continuation.yield(.toolInputStarted(call))

    case let .toolCallsCompleted(calls):
      for call in calls.map(\.call) {
        continuation.yield(.toolInputCompleted(call))
      }

    default:
      break
    }
  }

  func completedToolCall(withID id: String, from snapshot: ConversationStreamSnapshot) -> Transcript.ToolCall? {
    for entry in snapshot.transcriptEntries {
      guard case let .toolCalls(toolCalls) = entry else { continue }
      if let call = toolCalls.calls.first(where: { $0.id == id || $0.callId == id }) {
        return call
      }
    }
    return nil
  }

  func executeToolCalls(
    _ calls: [Transcript.ToolCall],
    recordTranscript: Bool,
    eventSink: ((AgentToolExecutionEvent) -> Void)?,
  ) async throws -> ToolExecutionOutcome {
    guard calls.isEmpty == false else {
      return .outputs([])
    }

    setCurrentToolCalls(calls)
    defer { setCurrentToolCalls([]) }

    let delegate = toolExecutionDelegate
    await delegate?.didGenerateToolCalls(calls, in: self)

    var decisions: [ToolExecutionDecision] = []
    decisions.reserveCapacity(calls.count)

    for call in calls {
      if delegate != nil {
        eventSink?(.approvalRequested(call))
      }
      let decision = await delegate?.toolCallDecision(for: call, in: self) ?? .execute
      if case .stop = decision {
        if recordTranscript {
          await modelSession.applyRuntimeResponse(ModelResponse(
            transcriptEntries: [.toolCalls(.init(calls: calls))],
            finishReason: .completed,
          ))
          syncFromModelSession()
        }
        return .stop(calls: calls)
      }
      decisions.append(decision)
    }

    if recordTranscript {
      await modelSession.applyRuntimeResponse(ModelResponse(
        transcriptEntries: [.toolCalls(.init(calls: calls))],
        finishReason: .completed,
      ))
      syncFromModelSession()
    }

    let results: [ToolExecutionResult]
    if configuration.toolExecutionPolicy.allowsParallelExecution {
      results = try await executeToolCallsInParallel(
        calls,
        decisions: decisions,
        delegate: delegate,
        eventSink: eventSink,
      )
    } else {
      results = try await executeToolCallsSerially(calls, decisions: decisions, delegate: delegate, eventSink: eventSink)
    }

    let outputs = results.map(\.output)
    setCurrentToolOutputs(outputs)

    if recordTranscript {
      await modelSession.applyRuntimeResponse(ModelResponse(
        transcriptEntries: outputs.map(Transcript.Entry.toolOutput),
        finishReason: .completed,
      ))
      syncFromModelSession()
    }

    return .outputs(results)
  }

  func executeToolCallsSerially(
    _ calls: [Transcript.ToolCall],
    decisions: [ToolExecutionDecision],
    delegate: (any ToolExecutionDelegate)?,
    eventSink: ((AgentToolExecutionEvent) -> Void)?,
  ) async throws -> [ToolExecutionResult] {
    var results: [ToolExecutionResult] = []
    results.reserveCapacity(calls.count)

    for (index, call) in calls.enumerated() {
      let result = try await executeToolCall(call, decision: decisions[index], delegate: delegate, eventSink: eventSink)
      results.append(result)
    }

    return results
  }

  func executeToolCallsInParallel(
    _ calls: [Transcript.ToolCall],
    decisions: [ToolExecutionDecision],
    delegate: (any ToolExecutionDelegate)?,
    eventSink: ((AgentToolExecutionEvent) -> Void)?,
  ) async throws -> [ToolExecutionResult] {
    var indexedResults: [(Int, ToolExecutionResult)] = []
    indexedResults.reserveCapacity(calls.count)

    try await withThrowingTaskGroup(of: (Int, ToolExecutionResult).self) { group in
      for (index, call) in calls.enumerated() {
        let decision = decisions[index]
        eventSink?(.executionStarted(call))
        group.addTask {
          let result = try await self.executeToolCall(
            call,
            decision: decision,
            delegate: delegate,
            eventSink: nil,
          )
          return (index, result)
        }
      }

      for try await indexedResult in group {
        let result = indexedResult.1
        eventSink?(.outputDelta(result.output))
        eventSink?(.callCompleted(result.call))
        eventSink?(.output(result.output))
        indexedResults.append(indexedResult)
      }
    }

    return indexedResults
      .sorted { $0.0 < $1.0 }
      .map(\.1)
  }

  func executeToolCall(
    _ call: Transcript.ToolCall,
    decision: ToolExecutionDecision,
    delegate: (any ToolExecutionDelegate)?,
    eventSink: ((AgentToolExecutionEvent) -> Void)?,
  ) async throws -> ToolExecutionResult {
    eventSink?(.executionStarted(call))

    switch decision {
    case .stop:
      let output = makeToolOutput(for: call, segment: .text(.init(content: "")))
      eventSink?(.outputDelta(output))
      eventSink?(.callCompleted(call))
      eventSink?(.output(output))
      return ToolExecutionResult(call: call, output: output)

    case .provideOutput(let segments):
      let output = makeToolOutput(for: call, segment: segments.first ?? .text(.init(content: "")))
      await delegate?.didExecuteToolCall(call, output: output, in: self)
      eventSink?(.outputDelta(output))
      eventSink?(.callCompleted(call))
      eventSink?(.output(output))
      return ToolExecutionResult(call: call, output: output)

    case .execute:
      guard let tool = tools.first(where: { $0.name == call.toolName }) else {
        return try await handleMissingTool(call, delegate: delegate, eventSink: eventSink)
      }

      var attempt = 0
      while true {
        attempt += 1

        do {
          let segments = try await tool.makeOutputSegments(from: call.arguments)
          let output = makeToolOutput(for: call, toolName: tool.name, segment: segments.first ?? .text(.init(content: "")))
          await delegate?.didExecuteToolCall(call, output: output, in: self)
          eventSink?(.outputDelta(output))
          eventSink?(.callCompleted(call))
          eventSink?(.output(output))
          return ToolExecutionResult(call: call, output: output)
        } catch is CancellationError {
          throw CancellationError()
        } catch let rejection as ToolRunRejection {
          let output = makeToolOutput(for: call, toolName: tool.name, segment: .structure(.init(content: rejection.generatedContent)))
          await delegate?.didExecuteToolCall(call, output: output, in: self)
          eventSink?(.outputDelta(output))
          eventSink?(.callCompleted(call))
          eventSink?(.output(output))
          return ToolExecutionResult(call: call, output: output)
        } catch {
          await delegate?.didFailToolCall(call, error: error, in: self)
          eventSink?(.executionFailed(call, error))

          if attempt < configuration.toolExecutionPolicy.retryPolicy.maximumAttempts {
            continue
          }

          if configuration.stopOnToolError, configuration.toolExecutionPolicy.failureBehavior == .throwError {
            throw ToolCallError(tool: tool, underlyingError: error)
          }

          let output = makeToolOutput(for: call, toolName: tool.name, segment: .text(.init(content: error.localizedDescription)))
          await delegate?.didExecuteToolCall(call, output: output, in: self)
          eventSink?(.outputDelta(output))
          eventSink?(.callCompleted(call))
          eventSink?(.output(output))
          return ToolExecutionResult(call: call, output: output)
        }
      }
    }
  }

  func handleMissingTool(
    _ call: Transcript.ToolCall,
    delegate: (any ToolExecutionDelegate)?,
    eventSink: ((AgentToolExecutionEvent) -> Void)?,
  ) async throws -> ToolExecutionResult {
    let error = MissingToolError(toolName: call.toolName)

    if configuration.stopOnToolError, configuration.toolExecutionPolicy.missingToolBehavior == .throwError {
      await delegate?.didFailToolCall(call, error: error, in: self)
      eventSink?(.executionFailed(call, error))
      throw ToolCallError(toolName: call.toolName, underlyingError: error)
    } else {
      let output = makeToolOutput(
        for: call,
        segment: .text(.init(content: "Tool not found: \(call.toolName)")),
      )
      await delegate?.didExecuteToolCall(call, output: output, in: self)
      eventSink?(.outputDelta(output))
      eventSink?(.callCompleted(call))
      eventSink?(.output(output))
      return ToolExecutionResult(call: call, output: output)
    }
  }

  func makeToolOutput(
    for call: Transcript.ToolCall,
    toolName: String? = nil,
    segment: Transcript.Segment,
  ) -> Transcript.ToolOutput {
    Transcript.ToolOutput(
      id: call.id,
      callId: call.callId,
      toolName: toolName ?? call.toolName,
      segment: segment,
      status: .completed,
    )
  }

  func result<Content>(
    from rawContent: GeneratedContent,
    as type: Content.Type,
    steps: [AgentStepResult],
  ) async throws -> AgentResult<Content> where Content: Generable & Sendable {
    let content: Content
    if type == String.self, case let .string(text) = rawContent.kind {
      content = text as! Content
    } else if type == String.self {
      content = rawContent.jsonString as! Content
    } else {
      content = try Content(rawContent)
    }

    return AgentResult(
      content: content,
      rawContent: rawContent,
      transcript: modelSession.transcript,
      steps: steps,
      toolCalls: steps.flatMap(\.toolCalls),
      toolOutputs: steps.flatMap(\.toolOutputs),
      tokenUsage: modelSession.tokenUsage,
      responseMetadata: modelSession.responseMetadata,
      iterationCount: steps.count,
    )
  }

  func stepResult(
    index: Int,
    response: ModelResponse,
    toolCalls: [Transcript.ToolCall] = [],
    toolOutputs: [Transcript.ToolOutput] = [],
  ) async -> AgentStepResult {
    var entries = response.transcriptEntries
    entries.append(contentsOf: response.reasoning.map(Transcript.Entry.reasoning))
    if response.toolCalls.isEmpty == false {
      entries.append(.toolCalls(.init(calls: response.toolCalls.map(\.call))))
    }
    if let content = response.content {
      entries.append(.response(.init(segments: [responseSegment(from: content)])))
    }
    entries.append(contentsOf: toolOutputs.map(Transcript.Entry.toolOutput))
    return await stepResult(
      index: index,
      transcriptEntries: entries,
      toolCalls: toolCalls,
      toolOutputs: toolOutputs,
      finishReason: response.finishReason,
    )
  }

  func stepResult(
    index: Int,
    transcriptEntries: [Transcript.Entry],
    toolCalls: [Transcript.ToolCall] = [],
    toolOutputs: [Transcript.ToolOutput] = [],
    finishReason: FinishReason,
  ) async -> AgentStepResult {
    AgentStepResult(
      index: index,
      transcriptEntries: transcriptEntries,
      toolCalls: toolCalls,
      toolOutputs: toolOutputs,
      tokenUsage: modelSession.tokenUsage,
      responseMetadata: modelSession.responseMetadata,
      finishReason: finishReason,
    )
  }

  func responseSegment(from rawContent: GeneratedContent) -> Transcript.Segment {
    if case let .string(text) = rawContent.kind {
      return .text(.init(content: text))
    }
    return .structure(.init(content: rawContent))
  }

  static func partialContent<Content>(
    from rawContent: GeneratedContent,
    as type: Content.Type,
  ) -> Content.PartiallyGenerated? where Content: Generable {
    if type == String.self {
      if case let .string(text) = rawContent.kind {
        return (text as! Content).asPartiallyGenerated()
      }
      return (rawContent.jsonString as! Content).asPartiallyGenerated()
    }
    if let partial = try? Content(rawContent).asPartiallyGenerated() {
      return partial
    }
    if case let .string(text) = rawContent.kind {
      return partialStructuredGeneration(from: text, as: type)?.content
    }
    return nil
  }

  static func promptEntry(for prompt: Prompt) -> Transcript.Prompt {
    Transcript.Prompt(
      input: prompt.description,
      sources: Data(),
      prompt: prompt.description,
    )
  }

  static func promptEntry<Schema>(
    input: String,
    sources: [Schema.DecodedGrounding],
    schema: Schema,
    prompt: Prompt,
  ) throws -> Transcript.Prompt where Schema: TranscriptSchema & GroundingSupportingSchema {
    try Transcript.Prompt(
      input: input,
      sources: schema.encodeGrounding(sources),
      prompt: prompt.description,
    )
  }

  func structuredOutputRequest<Content>(
    for type: Content.Type,
    includeSchemaInPrompt: Bool,
  ) -> StructuredOutputRequest? where Content: Generable {
    guard type != String.self else { return nil }
    return StructuredOutputRequest(
      format: .generatedContent(
        typeName: String(describing: type),
        schema: Content.generationSchema,
        strict: true,
      ),
      includeSchemaInPrompt: includeSchemaInPrompt,
    )
  }

  func beginRunning() {
    withMutation(keyPath: \.isRunning) {
      state.withLock { $0.isRunning = true }
    }
  }

  func endRunning() {
    withMutation(keyPath: \.isRunning) {
      state.withLock {
        $0.isRunning = false
        $0.currentIteration = 0
        $0.currentToolCalls = []
        $0.currentToolOutputs = []
      }
    }
  }

  func setCurrentIteration(_ iteration: Int) {
    withMutation(keyPath: \.currentIteration) {
      state.withLock { $0.currentIteration = iteration }
    }
  }

  func setCurrentToolCalls(_ calls: [Transcript.ToolCall]) {
    withMutation(keyPath: \.currentToolCalls) {
      state.withLock { $0.currentToolCalls = calls }
    }
  }

  func setCurrentToolOutputs(_ outputs: [Transcript.ToolOutput]) {
    withMutation(keyPath: \.currentToolOutputs) {
      state.withLock { $0.currentToolOutputs = outputs }
    }
  }

  func setLatestError(_ error: any Error) {
    withMutation(keyPath: \.latestError) {
      state.withLock { $0.latestError = error }
    }
  }

  func syncFromModelSession() {
    let transcript = modelSession.transcript
    let tokenUsage = modelSession.tokenUsage
    let responseMetadata = modelSession.responseMetadata
    withMutation(keyPath: \.transcript) {
      state.withLock {
        $0.transcript = transcript
        $0.tokenUsage = tokenUsage
        $0.responseMetadata = responseMetadata
      }
    }
  }
}

private struct AgentState: Sendable {
  var isRunning = false
  var transcript: Transcript
  var tokenUsage: TokenUsage?
  var responseMetadata: ResponseMetadata?
  var currentIteration = 0
  var currentToolCalls: [Transcript.ToolCall] = []
  var currentToolOutputs: [Transcript.ToolOutput] = []
  var latestError: (any Error)?
}

private enum AgentSessionError: Error, LocalizedError, Sendable {
  case maxIterationsExceeded(Int)
  case noFinalResponse

  var errorDescription: String? {
    switch self {
    case let .maxIterationsExceeded(maxIterations):
      "Agent exceeded the maximum iteration count of \(maxIterations)."
    case .noFinalResponse:
      "The agent finished without a final response."
    }
  }
}

private struct MissingToolError: Error, LocalizedError {
  var toolName: String

  var errorDescription: String? {
    "Tool not found: \(toolName)"
  }
}

private struct AgentStopPolicy: Sendable {
  var maxIterations: Int

  func shouldStop(after iteration: Int) -> Bool {
    iteration >= maxIterations
  }
}
