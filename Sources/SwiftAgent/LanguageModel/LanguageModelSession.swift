import Foundation
import Observation

/// Main session that coordinates a language model, tools, instructions, transcript, and usage state.
@Observable
public final class LanguageModelSession: @unchecked Sendable {
  @ObservationIgnored private let model: any LanguageModel
  @ObservationIgnored private let state: Locked<State>
  @ObservationIgnored private let toolExecutionDelegateStorage = Locked<(any ToolExecutionDelegate)?>(nil)

  /// Tools available to the model during this session.
  public let tools: [any Tool]

  /// Instructions applied to each turn.
  public let instructions: Instructions?

  /// Policy used when providers emit tool calls for the session to execute.
  public let toolExecutionPolicy: ToolExecutionPolicy

  /// Delegate that can approve, stop, or provide output for tool calls.
  public var toolExecutionDelegate: (any ToolExecutionDelegate)? {
    get { toolExecutionDelegateStorage.withLock { $0 } }
    set { toolExecutionDelegateStorage.withLock { $0 = newValue } }
  }

  /// Whether this session is currently waiting on model output.
  public var isResponding: Bool {
    access(keyPath: \.isResponding)
    return state.withLock { $0.isResponding }
  }

  /// The current transcript assembled by this session.
  public var transcript: Transcript {
    access(keyPath: \.transcript)
    return state.withLock { $0.transcript }
  }

  /// Cumulative token usage reported by the model during this session.
  public var tokenUsage: TokenUsage? {
    access(keyPath: \.tokenUsage)
    return state.withLock { $0.tokenUsage }
  }

  /// Metadata reported for the latest provider response in this session.
  public var responseMetadata: ResponseMetadata? {
    access(keyPath: \.responseMetadata)
    return state.withLock { $0.responseMetadata }
  }

  /// Creates a session with a model, tools, and instructions.
  public init(
    model: any LanguageModel,
    tools: [any Tool] = [],
    instructions: Instructions? = nil,
    toolExecutionPolicy: ToolExecutionPolicy = .automatic,
  ) {
    self.model = model
    self.tools = tools
    self.instructions = instructions
    self.toolExecutionPolicy = toolExecutionPolicy
    state = Locked(State(transcript: Self.initialTranscript(instructions: instructions, tools: tools)))
  }

  /// Creates a session with a model, tools, and string instructions.
  public convenience init(
    model: any LanguageModel,
    tools: [any Tool] = [],
    instructions: String,
    toolExecutionPolicy: ToolExecutionPolicy = .automatic,
  ) {
    self.init(
      model: model,
      tools: tools,
      instructions: Instructions(instructions),
      toolExecutionPolicy: toolExecutionPolicy,
    )
  }

  /// Creates a session with instructions from an ``InstructionsBuilder``.
  public convenience init(
    model: any LanguageModel,
    tools: [any Tool] = [],
    toolExecutionPolicy: ToolExecutionPolicy = .automatic,
    @InstructionsBuilder instructions: () throws -> Instructions,
  ) rethrows {
    try self.init(model: model, tools: tools, instructions: instructions(), toolExecutionPolicy: toolExecutionPolicy)
  }

  /// Prepares the underlying model for an upcoming prompt prefix when supported.
  public func prewarm(promptPrefix: Prompt? = nil) {
    model.prewarm(for: self, promptPrefix: promptPrefix)
  }

  /// Generates a complete response.
  @discardableResult
  public func respond<Content>(
    to prompt: Prompt,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<Content> where Content: Generable & Sendable {
    try await respond(
      to: prompt,
      promptEntry: Self.promptEntry(for: prompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  private func respond<Content>(
    to prompt: Prompt,
    promptEntry: Transcript.Prompt,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<Content> where Content: Generable & Sendable {
    beginResponding()
    defer { endResponding() }

    appendPrompt(promptEntry)

    let response = try await model.respond(
      within: self,
      to: prompt,
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )

    recordProviderEntries(response.transcriptEntries)
    recordResponse(rawContent: response.rawContent, status: .completed)
    recordTokenUsage(response.tokenUsage)
    recordResponseMetadata(response.responseMetadata)

    return response
  }

  /// Streams a response and derives each public snapshot from transcript and usage state.
  public func streamResponse<Content>(
    to prompt: Prompt,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    streamResponse(
      to: prompt,
      promptEntry: Self.promptEntry(for: prompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  private func streamResponse<Content>(
    to prompt: Prompt,
    promptEntry: Transcript.Prompt,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    appendPrompt(promptEntry)

    if let eventStreamingModel = model as? any EventStreamingLanguageModel {
      return streamEventResponse(
        eventStreamingModel,
        to: prompt,
        generating: type,
        includeSchemaInPrompt: includeSchemaInPrompt,
        options: options,
      )
    }

    let upstream = model.streamResponse(
      within: self,
      to: prompt,
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )

    let relay = AsyncThrowingStream<ResponseStream<Content>.Snapshot, any Error> { continuation in
      Task {
        self.beginResponding()
        defer { self.endResponding() }

        do {
          var lastSnapshot: ResponseStream<Content>.Snapshot?
          var pendingSnapshot: ResponseStream<Content>.Snapshot?
          var lastYield: ContinuousClock.Instant?
          let clock = ContinuousClock()

          func yieldSnapshot(_ snapshot: ResponseStream<Content>.Snapshot, force: Bool = false) {
            let interval = options.minimumStreamingSnapshotInterval
            let now = clock.now
            if force || interval == nil || lastYield == nil || now - lastYield! >= interval! {
              lastYield = now
              pendingSnapshot = nil
              continuation.yield(snapshot)
            } else {
              pendingSnapshot = snapshot
            }
          }

          for try await snapshot in upstream {
            self.recordProviderEntries(snapshot.transcriptEntries)
            self.recordTokenUsage(snapshot.tokenUsage)
            self.recordResponseMetadata(snapshot.responseMetadata)

            if let rawContent = snapshot.rawContent {
              self.recordResponse(rawContent: rawContent, status: .inProgress)
            }

            let derived = ResponseStream<Content>.Snapshot(
              content: snapshot.content,
              rawContent: snapshot.rawContent,
              transcript: self.transcript,
              tokenUsage: self.tokenUsage,
              responseMetadata: self.responseMetadata,
              transcriptEntries: snapshot.transcriptEntries,
            )
            if derived.rawContent != nil || lastSnapshot == nil {
              lastSnapshot = derived
            }
            yieldSnapshot(derived)
          }

          if let rawContent = lastSnapshot?.rawContent {
            self.recordResponse(rawContent: rawContent, status: .completed)
            yieldSnapshot(ResponseStream<Content>.Snapshot(
              content: lastSnapshot?.content,
              rawContent: rawContent,
              transcript: self.transcript,
              tokenUsage: self.tokenUsage,
              responseMetadata: self.responseMetadata,
            ), force: true)
          } else if let pendingSnapshot {
            yieldSnapshot(pendingSnapshot, force: true)
          }

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }

    return ResponseStream(stream: relay)
  }

  /// Generates a complete string response.
  @discardableResult
  public func respond(
    to prompt: Prompt,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<String> {
    try await respond(to: prompt, generating: String.self, includeSchemaInPrompt: true, options: options)
  }

  /// Generates a complete string response from a plain prompt.
  @discardableResult
  public func respond(
    to prompt: String,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<String> {
    try await respond(to: Prompt(prompt), options: options)
  }

  /// Generates a complete structured response from a plain prompt.
  @discardableResult
  public func respond<Content>(
    to prompt: String,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<Content> where Content: Generable & Sendable {
    try await respond(
      to: Prompt(prompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Generates a complete string response from a prompt with one image.
  @discardableResult
  public func respond(
    to prompt: String,
    image: Transcript.ImageSegment,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<String> {
    try await respond(to: prompt, images: [image], options: options)
  }

  /// Generates a complete string response from a prompt with images.
  @discardableResult
  public func respond(
    to prompt: String,
    images: [Transcript.ImageSegment],
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<String> {
    try await respond(
      to: prompt,
      images: images,
      generating: String.self,
      includeSchemaInPrompt: true,
      options: options,
    )
  }

  /// Generates a complete structured response from a prompt with one image.
  @discardableResult
  public func respond<Content>(
    to prompt: String,
    image: Transcript.ImageSegment,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<Content> where Content: Generable & Sendable {
    try await respond(
      to: prompt,
      images: [image],
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Generates a complete structured response from a prompt with images.
  @discardableResult
  public func respond<Content>(
    to prompt: String,
    images: [Transcript.ImageSegment],
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<Content> where Content: Generable & Sendable {
    let renderedPrompt = Prompt(prompt)
    return try await respond(
      to: renderedPrompt,
      promptEntry: Self.promptEntry(for: renderedPrompt, images: images),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Streams a string response.
  public func streamResponse(
    to prompt: Prompt,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<String> {
    streamResponse(to: prompt, generating: String.self, includeSchemaInPrompt: true, options: options)
  }

  /// Streams a string response from a plain prompt.
  public func streamResponse(
    to prompt: String,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<String> {
    streamResponse(to: Prompt(prompt), options: options)
  }

  /// Streams a structured response from a plain prompt.
  public func streamResponse<Content>(
    to prompt: String,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    streamResponse(
      to: Prompt(prompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Streams a string response from a prompt with one image.
  public func streamResponse(
    to prompt: String,
    image: Transcript.ImageSegment,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<String> {
    streamResponse(to: prompt, images: [image], options: options)
  }

  /// Streams a string response from a prompt with images.
  public func streamResponse(
    to prompt: String,
    images: [Transcript.ImageSegment],
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<String> {
    streamResponse(
      to: prompt,
      images: images,
      generating: String.self,
      includeSchemaInPrompt: true,
      options: options,
    )
  }

  /// Streams a structured response from a prompt with one image.
  public func streamResponse<Content>(
    to prompt: String,
    image: Transcript.ImageSegment,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    streamResponse(
      to: prompt,
      images: [image],
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Streams a structured response from a prompt with images.
  public func streamResponse<Content>(
    to prompt: String,
    images: [Transcript.ImageSegment],
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    let renderedPrompt = Prompt(prompt)
    return streamResponse(
      to: renderedPrompt,
      promptEntry: Self.promptEntry(for: renderedPrompt, images: images),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Builds a provider feedback attachment.
  public func logFeedbackAttachment(
    sentiment: LanguageModelFeedback.Sentiment?,
    issues: [LanguageModelFeedback.Issue] = [],
    desiredOutput: Transcript.Entry? = nil,
  ) -> Data {
    model.logFeedbackAttachment(
      within: self,
      sentiment: sentiment,
      issues: issues,
      desiredOutput: desiredOutput,
    )
  }
}

public extension LanguageModelSession {
  /// Generates a text response while storing typed grounding values next to the prompt transcript entry.
  @discardableResult
  func respond<SessionSchema>(
    to input: String,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) async throws -> Response<String> where SessionSchema: LanguageModelSessionSchema & GroundingSupportingSchema {
    let renderedPrompt = prompt(input, sources)
    return try await respond(
      to: renderedPrompt,
      promptEntry: try Self.promptEntry(input: input, sources: sources, schema: schema, prompt: renderedPrompt),
      generating: String.self,
      options: options,
    )
  }

  /// Generates a structured response while storing typed grounding values next to the prompt transcript entry.
  @discardableResult
  func respond<SessionSchema, Content>(
    to input: String,
    generating type: Content.Type,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) async throws -> Response<Content>
    where SessionSchema: LanguageModelSessionSchema & GroundingSupportingSchema,
    Content: Generable & Sendable {
    let renderedPrompt = prompt(input, sources)
    return try await respond(
      to: renderedPrompt,
      promptEntry: try Self.promptEntry(input: input, sources: sources, schema: schema, prompt: renderedPrompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Generates a structured response registered on a session schema while storing typed groundings.
  @discardableResult
  func respond<SessionSchema, Output>(
    to input: String,
    generating type: KeyPath<SessionSchema.StructuredOutputs, Output.Type>,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) async throws -> Response<Output.Schema>
    where SessionSchema: LanguageModelSessionSchema & GroundingSupportingSchema,
    Output: StructuredOutput,
    Output.Schema: Sendable {
    try await respond(
      to: input,
      generating: Output.Schema.self,
      schema: schema,
      groundingWith: sources,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
      embeddingInto: prompt,
    )
  }

  /// Streams a text response while storing typed grounding values next to the prompt transcript entry.
  func streamResponse<SessionSchema>(
    to input: String,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) throws -> sending ResponseStream<String> where SessionSchema: LanguageModelSessionSchema & GroundingSupportingSchema {
    let renderedPrompt = prompt(input, sources)
    return try streamResponse(
      to: renderedPrompt,
      promptEntry: Self.promptEntry(input: input, sources: sources, schema: schema, prompt: renderedPrompt),
      generating: String.self,
      options: options,
    )
  }

  /// Streams a structured response while storing typed grounding values next to the prompt transcript entry.
  func streamResponse<SessionSchema, Content>(
    to input: String,
    generating type: Content.Type,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) throws -> sending ResponseStream<Content>
    where SessionSchema: LanguageModelSessionSchema & GroundingSupportingSchema,
    Content: Generable & Sendable,
    Content.PartiallyGenerated: Sendable {
    let renderedPrompt = prompt(input, sources)
    return try streamResponse(
      to: renderedPrompt,
      promptEntry: Self.promptEntry(input: input, sources: sources, schema: schema, prompt: renderedPrompt),
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  /// Streams a structured response registered on a session schema while storing typed groundings.
  func streamResponse<SessionSchema, Output>(
    to input: String,
    generating type: KeyPath<SessionSchema.StructuredOutputs, Output.Type>,
    schema: SessionSchema,
    groundingWith sources: [SessionSchema.DecodedGrounding],
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
    @PromptBuilder embeddingInto prompt: @Sendable (_ input: String, _ sources: [SessionSchema.DecodedGrounding])
      -> Prompt,
  ) throws -> sending ResponseStream<Output.Schema>
    where SessionSchema: LanguageModelSessionSchema & GroundingSupportingSchema,
    Output: StructuredOutput,
    Output.Schema: Sendable,
    Output.Schema.PartiallyGenerated: Sendable {
    try streamResponse(
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

public extension LanguageModelSession {
  /// A complete model response.
  struct Response<Content>: Sendable where Content: Generable & Sendable {
    /// Decoded response content.
    public let content: Content

    /// Raw content produced by the provider.
    public let rawContent: GeneratedContent

    /// Transcript entries emitted by the provider, excluding the session-owned prompt and final response.
    public let transcriptEntries: [Transcript.Entry]

    /// Token usage reported for this response.
    public let tokenUsage: TokenUsage?

    /// Provider metadata reported for this response.
    public let responseMetadata: ResponseMetadata?

    /// Creates a complete response.
    public init(
      content: Content,
      rawContent: GeneratedContent,
      transcriptEntries: [Transcript.Entry] = [],
      tokenUsage: TokenUsage? = nil,
      responseMetadata: ResponseMetadata? = nil,
    ) {
      self.content = content
      self.rawContent = rawContent
      self.transcriptEntries = transcriptEntries
      self.tokenUsage = tokenUsage
      self.responseMetadata = responseMetadata
    }
  }

  /// An async response stream.
  struct ResponseStream<Content>: Sendable where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    private let fallbackSnapshot: Snapshot?
    private let stream: AsyncThrowingStream<Snapshot, any Error>?

    /// Creates a stream with one already-complete snapshot.
    public init(
      content: Content,
      rawContent: GeneratedContent,
      tokenUsage: TokenUsage? = nil,
      responseMetadata: ResponseMetadata? = nil,
    ) {
      fallbackSnapshot = Snapshot(
        content: content.asPartiallyGenerated(),
        rawContent: rawContent,
        tokenUsage: tokenUsage,
        responseMetadata: responseMetadata,
      )
      stream = nil
    }

    /// Creates a stream from an async sequence of snapshots.
    public init(stream: AsyncThrowingStream<Snapshot, any Error>) {
      fallbackSnapshot = nil
      self.stream = stream
    }

    /// A transcript-derived view of the current stream state.
    public struct Snapshot: Sendable {
      /// Current partially generated response content.
      public var content: Content.PartiallyGenerated?

      /// Current raw generated content.
      public var rawContent: GeneratedContent?

      /// Transcript state after applying this snapshot.
      public var transcript: Transcript

      /// Token usage state after applying this snapshot.
      public var tokenUsage: TokenUsage?

      /// Provider metadata state after applying this snapshot.
      public var responseMetadata: ResponseMetadata?

      /// Provider-emitted transcript entries represented by this snapshot.
      public var transcriptEntries: [Transcript.Entry]

      /// Creates a stream snapshot.
      public init(
        content: Content.PartiallyGenerated? = nil,
        rawContent: GeneratedContent? = nil,
        transcript: Transcript = Transcript(),
        tokenUsage: TokenUsage? = nil,
        responseMetadata: ResponseMetadata? = nil,
        transcriptEntries: [Transcript.Entry] = [],
      ) {
        self.content = content
        self.rawContent = rawContent
        self.transcript = transcript
        self.tokenUsage = tokenUsage
        self.responseMetadata = responseMetadata
        self.transcriptEntries = transcriptEntries
      }
    }
  }

  /// Errors produced by main model sessions.
  enum GenerationError: Error, LocalizedError {
    /// Context describing a generation failure.
    public struct Context: Sendable {
      public let debugDescription: String

      public init(debugDescription: String) {
        self.debugDescription = debugDescription
      }
    }

    /// Context describing a provider refusal with transcript entries that explain it.
    public struct Refusal: Sendable {
      public let transcriptEntries: [Transcript.Entry]

      public init(transcriptEntries: [Transcript.Entry]) {
        self.transcriptEntries = transcriptEntries
      }

      /// A complete textual explanation extracted from refusal transcript entries.
      public var explanation: Response<String> {
        get async throws {
          let text = transcriptEntries.compactMap { entry in
            guard case .response(let response) = entry else {
              return nil
            }
            return response.text
          }.joined(separator: "\n")

          let explanationText = text.isEmpty ? "No explanation available" : text
          return Response(
            content: explanationText,
            rawContent: GeneratedContent(explanationText),
            transcriptEntries: transcriptEntries,
          )
        }
      }

      /// A single-snapshot stream containing the refusal explanation.
      public var explanationStream: ResponseStream<String> {
        let text = transcriptEntries.compactMap { entry in
          guard case .response(let response) = entry else {
            return nil
          }
          return response.text
        }.joined(separator: "\n")
        let explanationText = text.isEmpty ? "No explanation available" : text
        return ResponseStream(content: explanationText, rawContent: GeneratedContent(explanationText))
      }
    }

    case exceededContextWindowSize(Context)
    case assetsUnavailable(Context)
    case guardrailViolation(Context)
    case unsupportedGuide(Context)
    case unsupportedLanguageOrLocale(Context)
    case decodingFailure(Context)
    case rateLimited(Context)
    case concurrentRequests(Context)
    case refusal(Refusal, Context)

    public var errorDescription: String? { nil }
    public var recoverySuggestion: String? { nil }
    public var failureReason: String? { nil }
  }

  /// Error thrown when a session-owned tool call cannot be completed.
  struct ToolCallError: Error, LocalizedError {
    /// The tool name emitted by the model.
    public let toolName: String

    /// The underlying execution failure.
    public let underlyingError: any Error

    /// Creates a tool call error for a registered tool.
    public init(tool: any Tool, underlyingError: any Error) {
      toolName = tool.name
      self.underlyingError = underlyingError
    }

    /// Creates a tool call error for a missing or unavailable tool.
    public init(toolName: String, underlyingError: any Error) {
      self.toolName = toolName
      self.underlyingError = underlyingError
    }

    public var errorDescription: String? {
      "Tool '\(toolName)' failed: \(underlyingError.localizedDescription)"
    }
  }

  /// Output from a session-owned tool call.
  struct ToolExecutionResult: Sendable, Equatable {
    /// The model-emitted tool call.
    public var call: Transcript.ToolCall

    /// The output recorded for the call.
    public var output: Transcript.ToolOutput

    public init(call: Transcript.ToolCall, output: Transcript.ToolOutput) {
      self.call = call
      self.output = output
    }
  }

  /// Result of asking the session to handle emitted tool calls.
  enum ToolExecutionOutcome: Sendable, Equatable {
    /// Execution stopped after recording tool calls.
    case stop(calls: [Transcript.ToolCall])

    /// Tool outputs were produced for the calls.
    case outputs([ToolExecutionResult])
  }
}

public extension LanguageModelSession {
  /// Executes model-emitted tool calls through this session's tool policy.
  ///
  /// Providers should call this after emitting tool calls instead of executing tools directly.
  /// The session records tool-call and tool-output transcript entries when requested.
  func executeToolCalls(
    _ calls: [Transcript.ToolCall],
    recordTranscript: Bool = true,
  ) async throws -> ToolExecutionOutcome {
    guard calls.isEmpty == false else {
      return .outputs([])
    }

    let delegate = toolExecutionDelegate
    await delegate?.didGenerateToolCalls(calls, in: self)

    var decisions: [ToolExecutionDecision] = []
    decisions.reserveCapacity(calls.count)

    for call in calls {
      let decision = await delegate?.toolCallDecision(for: call, in: self) ?? .execute
      if case .stop = decision {
        if recordTranscript {
          recordProviderEntries([.toolCalls(.init(calls: calls))])
        }
        return .stop(calls: calls)
      }
      decisions.append(decision)
    }

    if recordTranscript {
      recordProviderEntries([.toolCalls(.init(calls: calls))])
    }

    let results: [ToolExecutionResult]
    if toolExecutionPolicy.allowsParallelExecution {
      results = try await executeToolCallsInParallel(calls, decisions: decisions, delegate: delegate)
    } else {
      results = try await executeToolCallsSerially(calls, decisions: decisions, delegate: delegate)
    }

    if recordTranscript {
      recordProviderEntries(results.map { .toolOutput($0.output) })
    }

    return .outputs(results)
  }
}

extension LanguageModelSession.ResponseStream: AsyncSequence {
  public typealias Element = Snapshot

  public struct AsyncIterator: AsyncIteratorProtocol {
    private var fallbackSnapshot: Snapshot?
    private var streamIterator: AsyncThrowingStream<Snapshot, any Error>.AsyncIterator?

    init(fallbackSnapshot: Snapshot?, stream: AsyncThrowingStream<Snapshot, any Error>?) {
      self.fallbackSnapshot = fallbackSnapshot
      streamIterator = stream?.makeAsyncIterator()
    }

    public mutating func next() async throws -> Snapshot? {
      if var streamIterator {
        let value = try await streamIterator.next()
        self.streamIterator = streamIterator
        return value
      }

      defer { fallbackSnapshot = nil }
      return fallbackSnapshot
    }
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(fallbackSnapshot: fallbackSnapshot, stream: stream)
  }

  /// Collects the final stream snapshot into a complete response.
  public func collect() async throws -> LanguageModelSession.Response<Content> {
    var lastSnapshot: Snapshot?

    for try await snapshot in self {
      lastSnapshot = snapshot
    }

    guard let lastSnapshot, let rawContent = lastSnapshot.rawContent else {
      throw ResponseStreamError.noSnapshots
    }

    let content: Content
    if let generated = lastSnapshot.content as? Content {
      content = generated
    } else {
      content = try Content(rawContent)
    }

    return LanguageModelSession.Response(
      content: content,
      rawContent: rawContent,
      transcriptEntries: lastSnapshot.transcriptEntries,
      tokenUsage: lastSnapshot.tokenUsage,
      responseMetadata: lastSnapshot.responseMetadata,
    )
  }
}

private extension LanguageModelSession {
  func streamEventResponse<Content>(
    _ eventStreamingModel: any EventStreamingLanguageModel,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) -> sending ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    let events = eventStreamingModel.streamEvents(
      within: self,
      to: prompt,
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )

    let relay = AsyncThrowingStream<ResponseStream<Content>.Snapshot, any Error> { continuation in
      Task {
        self.beginResponding()
        defer { self.endResponding() }

        let clock = ContinuousClock()
        var lastYield: ContinuousClock.Instant?
        var pendingSnapshot: ResponseStream<Content>.Snapshot?
        var lastSnapshot: ResponseStream<Content>.Snapshot?
        var accumulatedTextByID: [String: String] = [:]
        var textOrder: [String] = []
        var reasoningByID: [String: Transcript.Reasoning] = [:]
        var toolCallsByID: [String: Transcript.ToolCall] = [:]
        var toolCallOrder: [String] = []
        var toolArgumentBuffers: [String: String] = [:]
        var toolCallsEntryID: String?
        var currentContent: Content.PartiallyGenerated?
        var currentRawContent: GeneratedContent?
        var didEmitFinishedSnapshot = false

        func currentText() -> String {
          textOrder.map { accumulatedTextByID[$0] ?? "" }.joined()
        }

        func toolCallsEntry() -> Transcript.Entry? {
          let calls = toolCallOrder.compactMap { toolCallsByID[$0] }
          guard calls.isEmpty == false else { return nil }
          let id = toolCallsEntryID ?? "tool-calls-\(calls[0].id)"
          toolCallsEntryID = id
          return .toolCalls(.init(id: id, calls: calls))
        }

        func makeSnapshot(transcriptEntries: [Transcript.Entry] = []) -> ResponseStream<Content>.Snapshot {
          ResponseStream<Content>.Snapshot(
            content: currentContent,
            rawContent: currentRawContent,
            transcript: self.transcript,
            tokenUsage: self.tokenUsage,
            responseMetadata: self.responseMetadata,
            transcriptEntries: transcriptEntries,
          )
        }

        func yieldSnapshot(_ snapshot: ResponseStream<Content>.Snapshot, force: Bool = false) {
          let interval = options.minimumStreamingSnapshotInterval
          let now = clock.now
          if force || interval == nil || lastYield == nil || now - lastYield! >= interval! {
            lastYield = now
            pendingSnapshot = nil
            continuation.yield(snapshot)
          } else {
            pendingSnapshot = snapshot
          }
        }

        func updateContentFromText() {
          let text = currentText()
          if type == String.self {
            currentRawContent = GeneratedContent(text)
            currentContent = (text as! Content).asPartiallyGenerated()
          } else if let partial = partialStructuredGeneration(from: text, as: type) {
            currentRawContent = partial.rawContent
            currentContent = partial.content
          }
        }

        func recordAndYield(
          entries: [Transcript.Entry] = [],
          usage: TokenUsage? = nil,
          metadata: ResponseMetadata? = nil,
          force: Bool = false,
        ) {
          self.recordProviderEntries(entries)
          self.recordTokenUsage(usage)
          self.recordResponseMetadata(metadata)

          if let rawContent = currentRawContent {
            self.recordResponse(rawContent: rawContent, status: .inProgress)
          }

          let isMetadataOnlyUpdate = entries.isEmpty && (usage != nil || metadata != nil) && force == false
          let snapshot = if isMetadataOnlyUpdate {
            ResponseStream<Content>.Snapshot(
              transcript: self.transcript,
              tokenUsage: self.tokenUsage,
              responseMetadata: self.responseMetadata,
              transcriptEntries: entries,
            )
          } else {
            makeSnapshot(transcriptEntries: entries)
          }
          if snapshot.rawContent != nil || entries.isEmpty == false || usage != nil || metadata != nil || lastSnapshot == nil {
            if isMetadataOnlyUpdate == false {
              lastSnapshot = snapshot
            }
            yieldSnapshot(snapshot, force: force)
          }
        }

        do {
          for try await event in events {
            switch event {
            case .streamStarted(let warnings):
              let metadata = ResponseMetadata(warnings: warnings)
              recordAndYield(metadata: metadata)

            case .textStart(let id):
              if accumulatedTextByID[id] == nil {
                accumulatedTextByID[id] = ""
                textOrder.append(id)
              }
              recordAndYield()

            case .textDelta(let id, let delta):
              if accumulatedTextByID[id] == nil {
                accumulatedTextByID[id] = ""
                textOrder.append(id)
              }
              accumulatedTextByID[id, default: ""] += delta
              updateContentFromText()
              recordAndYield()

            case .textEnd:
              recordAndYield()

            case .structuredStart:
              recordAndYield()

            case .structuredDelta(_, let delta):
              currentRawContent = delta
              if let content = try? Content(delta) {
                currentContent = content.asPartiallyGenerated()
              }
              recordAndYield()

            case .structuredEnd:
              recordAndYield()

            case .reasoningStart(let id):
              let reasoning = Transcript.Reasoning(id: id, summary: [], encryptedReasoning: nil, status: .inProgress)
              reasoningByID[id] = reasoning
              recordAndYield(entries: [.reasoning(reasoning)])

            case .reasoningDelta(let id, let delta):
              var reasoning = reasoningByID[id] ??
                Transcript.Reasoning(id: id, summary: [], encryptedReasoning: nil, status: .inProgress)
              let existing = reasoning.summary.first ?? ""
              reasoning.summary = [existing + delta]
              reasoning.status = .inProgress
              reasoningByID[id] = reasoning
              recordAndYield(entries: [.reasoning(reasoning)])

            case .reasoningEnd(let id, let encryptedReasoning):
              var reasoning = reasoningByID[id] ??
                Transcript.Reasoning(id: id, summary: [], encryptedReasoning: nil, status: .completed)
              reasoning.encryptedReasoning = encryptedReasoning
              reasoning.status = .completed
              reasoningByID[id] = reasoning
              recordAndYield(entries: [.reasoning(reasoning)])

            case .toolInputStart(let id, let callId, let toolName):
              if toolCallsByID[id] == nil {
                toolCallOrder.append(id)
              }
              toolArgumentBuffers[id] = ""
              toolCallsByID[id] = Transcript.ToolCall(
                id: id,
                callId: callId ?? id,
                toolName: toolName,
                arguments: GeneratedContent(properties: [:]),
                partialArguments: "",
                status: .inProgress,
              )
              if let entry = toolCallsEntry() {
                recordAndYield(entries: [entry])
              }

            case .toolInputDelta(let id, let delta):
              toolArgumentBuffers[id, default: ""] += delta
              if var call = toolCallsByID[id] {
                call.partialArguments = toolArgumentBuffers[id]
                call.status = .inProgress
                toolCallsByID[id] = call
              }
              if let entry = toolCallsEntry() {
                recordAndYield(entries: [entry])
              }

            case .toolInputEnd(let id, let arguments):
              let parsedArguments = try arguments ?? GeneratedContent(json: toolArgumentBuffers[id] ?? "{}")
              if var call = toolCallsByID[id] {
                call.arguments = parsedArguments
                call.partialArguments = nil
                call.status = .completed
                toolCallsByID[id] = call
              }
              if let entry = toolCallsEntry() {
                recordAndYield(entries: [entry], force: true)
              }

            case .toolCall(let call):
              if toolCallsByID[call.id] == nil {
                toolCallOrder.append(call.id)
              }
              toolCallsByID[call.id] = call
              if let entry = toolCallsEntry() {
                recordAndYield(entries: [entry], force: true)
              }

            case .toolResult(let output):
              recordAndYield(entries: [.toolOutput(output)], force: true)

            case .responseMetadata(let metadata):
              recordAndYield(metadata: metadata)

            case .usage(let usage):
              recordAndYield(usage: usage)

            case .finished:
              if let rawContent = currentRawContent {
                self.recordResponse(rawContent: rawContent, status: .completed)
              }
              didEmitFinishedSnapshot = true
              yieldSnapshot(makeSnapshot(), force: true)

            case .raw:
              recordAndYield()

            case .failed(let error):
              throw error
            }
          }

          if didEmitFinishedSnapshot {
            // The provider already emitted an explicit finish event and the final snapshot was forced above.
          } else if let rawContent = currentRawContent {
            self.recordResponse(rawContent: rawContent, status: .completed)
            yieldSnapshot(makeSnapshot(), force: true)
          } else if let pendingSnapshot {
            yieldSnapshot(pendingSnapshot, force: true)
          }

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }

    return ResponseStream(stream: relay)
  }

  func beginResponding() {
    withMutation(keyPath: \.isResponding) {
      state.withLock { $0.responseDepth += 1 }
    }
  }

  func endResponding() {
    withMutation(keyPath: \.isResponding) {
      state.withLock { $0.responseDepth = max(0, $0.responseDepth - 1) }
    }
  }

  static func promptEntry(for prompt: Prompt) -> Transcript.Prompt {
    Transcript.Prompt(
      input: prompt.description,
      sources: Data(),
      prompt: prompt.description,
    )
  }

  static func promptEntry(for prompt: Prompt, images: [Transcript.ImageSegment]) -> Transcript.Prompt {
    Transcript.Prompt(
      input: prompt.description,
      sources: Data(),
      prompt: prompt.description,
      segments: promptSegments(text: prompt.description, images: images),
    )
  }

  static func promptEntry<SessionSchema>(
    input: String,
    sources: [SessionSchema.DecodedGrounding],
    schema: SessionSchema,
    prompt: Prompt,
  ) throws -> Transcript.Prompt where SessionSchema: LanguageModelSessionSchema & GroundingSupportingSchema {
    try Transcript.Prompt(
      input: input,
      sources: schema.encodeGrounding(sources),
      prompt: prompt.description,
    )
  }

  func appendPrompt(_ prompt: Transcript.Prompt) {
    withMutation(keyPath: \.transcript) {
      state.withLock { state in
        state.responseEntryID = UUID().uuidString
        state.responseSegmentID = UUID().uuidString
        state.transcript.entries.append(.prompt(prompt))
      }
    }
  }

  static func promptSegments(text: String, images: [Transcript.ImageSegment]) -> [Transcript.Segment] {
    var segments: [Transcript.Segment] = []
    if text.isEmpty == false {
      segments.append(.text(.init(content: text)))
    }
    segments.append(contentsOf: images.map(Transcript.Segment.image))
    return segments
  }

  static func initialTranscript(instructions: Instructions?, tools: [any Tool]) -> Transcript {
    guard let instructions else {
      return Transcript()
    }

    let toolDefinitions = tools
      .filter(\.includesSchemaInInstructions)
      .map(Transcript.ToolDefinition.init(tool:))
    let entry = Transcript.Entry.instructions(.init(
      segments: [.text(.init(content: instructions.description))],
      toolDefinitions: toolDefinitions,
    ))

    return Transcript(entries: [entry])
  }

  func recordProviderEntries(_ entries: [Transcript.Entry]) {
    guard entries.isEmpty == false else { return }

    withMutation(keyPath: \.transcript) {
      state.withLock { state in
        for entry in entries {
          state.transcript.upsert(entry)
        }
      }
    }
  }

  func recordResponse(rawContent: GeneratedContent, status: Transcript.Status) {
    let responseIDs = state.withLock { ($0.responseEntryID, $0.responseSegmentID) }
    let segment: Transcript.Segment

    if case .string(let text) = rawContent.kind {
      segment = .text(.init(id: responseIDs.1, content: text))
    } else {
      segment = .structure(.init(id: responseIDs.1, content: rawContent))
    }

    let entry = Transcript.Entry.response(.init(
      id: responseIDs.0,
      segments: [segment],
      status: status,
    ))
    withMutation(keyPath: \.transcript) {
      state.withLock { $0.transcript.upsert(entry) }
    }
  }

  func recordTokenUsage(_ usage: TokenUsage?) {
    guard let usage else { return }

    withMutation(keyPath: \.tokenUsage) {
      state.withLock { state in
        if state.tokenUsage == nil {
          state.tokenUsage = usage
        } else {
          state.tokenUsage?.merge(usage)
        }
      }
    }
  }

  func recordResponseMetadata(_ metadata: ResponseMetadata?) {
    guard let metadata else { return }

    withMutation(keyPath: \.responseMetadata) {
      state.withLock { state in
        state.responseMetadata = state.responseMetadata?.merging(metadata) ?? metadata
      }
    }
  }

  func executeToolCallsSerially(
    _ calls: [Transcript.ToolCall],
    decisions: [ToolExecutionDecision],
    delegate: (any ToolExecutionDelegate)?,
  ) async throws -> [ToolExecutionResult] {
    var results: [ToolExecutionResult] = []
    results.reserveCapacity(calls.count)

    for (index, call) in calls.enumerated() {
      let result = try await executeToolCall(call, decision: decisions[index], delegate: delegate)
      results.append(result)
    }

    return results
  }

  func executeToolCallsInParallel(
    _ calls: [Transcript.ToolCall],
    decisions: [ToolExecutionDecision],
    delegate: (any ToolExecutionDelegate)?,
  ) async throws -> [ToolExecutionResult] {
    var indexedResults: [(Int, ToolExecutionResult)] = []
    indexedResults.reserveCapacity(calls.count)

    try await withThrowingTaskGroup(of: (Int, ToolExecutionResult).self) { group in
      for (index, call) in calls.enumerated() {
        let decision = decisions[index]
        group.addTask {
          let result = try await self.executeToolCall(call, decision: decision, delegate: delegate)
          return (index, result)
        }
      }

      for try await indexedResult in group {
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
  ) async throws -> ToolExecutionResult {
    switch decision {
    case .stop:
      return ToolExecutionResult(call: call, output: makeToolOutput(for: call, segment: .text(.init(content: ""))))

    case .provideOutput(let segments):
      let output = makeToolOutput(for: call, segment: segments.first ?? .text(.init(content: "")))
      await delegate?.didExecuteToolCall(call, output: output, in: self)
      return ToolExecutionResult(call: call, output: output)

    case .execute:
      guard let tool = tools.first(where: { $0.name == call.toolName }) else {
        return try await handleMissingTool(call, delegate: delegate)
      }

      var attempt = 0
      while true {
        attempt += 1

        do {
          let segments = try await tool.makeOutputSegments(from: call.arguments)
          let output = makeToolOutput(for: call, toolName: tool.name, segment: segments.first ?? .text(.init(content: "")))
          await delegate?.didExecuteToolCall(call, output: output, in: self)
          return ToolExecutionResult(call: call, output: output)
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          await delegate?.didFailToolCall(call, error: error, in: self)

          if attempt < toolExecutionPolicy.retryPolicy.maximumAttempts {
            continue
          }

          switch toolExecutionPolicy.failureBehavior {
          case .throwError:
            throw ToolCallError(tool: tool, underlyingError: error)
          case .recordErrorOutput:
            let output = makeToolOutput(for: call, toolName: tool.name, segment: .text(.init(content: error.localizedDescription)))
            await delegate?.didExecuteToolCall(call, output: output, in: self)
            return ToolExecutionResult(call: call, output: output)
          }
        }
      }
    }
  }

  func handleMissingTool(
    _ call: Transcript.ToolCall,
    delegate: (any ToolExecutionDelegate)?,
  ) async throws -> ToolExecutionResult {
    let error = MissingToolError(toolName: call.toolName)

    switch toolExecutionPolicy.missingToolBehavior {
    case .recordErrorOutput:
      let output = makeToolOutput(
        for: call,
        segment: .text(.init(content: "Tool not found: \(call.toolName)")),
      )
      await delegate?.didExecuteToolCall(call, output: output, in: self)
      return ToolExecutionResult(call: call, output: output)

    case .throwError:
      await delegate?.didFailToolCall(call, error: error, in: self)
      throw ToolCallError(toolName: call.toolName, underlyingError: error)
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
}

private struct State: Sendable {
  var transcript: Transcript
  var tokenUsage: TokenUsage?
  var responseMetadata: ResponseMetadata?
  var responseDepth = 0
  var responseEntryID = UUID().uuidString
  var responseSegmentID = UUID().uuidString

  init(transcript: Transcript) {
    self.transcript = transcript
  }

  var isResponding: Bool {
    responseDepth > 0
  }
}

private enum ResponseStreamError: Error {
  case noSnapshots
}

private struct MissingToolError: Error, LocalizedError {
  var toolName: String

  var errorDescription: String? {
    "Tool not found: \(toolName)"
  }
}
