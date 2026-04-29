import Foundation
import Observation

/// Main session that coordinates a language model, tools, instructions, transcript, and usage state.
@Observable
public final class LanguageModelSession: @unchecked Sendable {
  @ObservationIgnored private let model: any LanguageModel
  @ObservationIgnored private let engine: ConversationEngine
  @ObservationIgnored private let state: Locked<State>

  /// Tools available to the model during this session.
  public let tools: [any Tool]

  /// Instructions applied to each turn.
  public let instructions: Instructions?

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
  ) {
    self.model = model
    self.tools = tools
    self.instructions = instructions
    engine = ConversationEngine(model: model, instructions: instructions, tools: tools)
    state = Locked(State(transcript: Self.initialTranscript(instructions: instructions, tools: tools)))
  }

  /// Creates a session with a model, tools, and string instructions.
  public convenience init(
    model: any LanguageModel,
    tools: [any Tool] = [],
    instructions: String,
  ) {
    self.init(
      model: model,
      tools: tools,
      instructions: Instructions(instructions),
    )
  }

  /// Creates a direct model session with tools declared by a session schema.
  public convenience init<SessionSchema>(
    model: any LanguageModel,
    schema: SessionSchema,
    instructions: Instructions? = nil,
  ) where SessionSchema: TranscriptSchema {
    self.init(model: model, tools: schema.tools, instructions: instructions)
  }

  /// Creates a direct model session with schema-declared tools and string instructions.
  public convenience init<SessionSchema>(
    model: any LanguageModel,
    schema: SessionSchema,
    instructions: String,
  ) where SessionSchema: TranscriptSchema {
    self.init(model: model, schema: schema, instructions: Instructions(instructions))
  }

  /// Creates a session with instructions from an ``InstructionsBuilder``.
  public convenience init(
    model: any LanguageModel,
    tools: [any Tool] = [],
    @InstructionsBuilder instructions: () throws -> Instructions,
  ) rethrows {
    try self.init(model: model, tools: tools, instructions: instructions())
  }

  /// Prepares the underlying model for an upcoming prompt prefix when supported.
  public func prewarm(promptPrefix: Prompt? = nil) {
    model.prewarm(for: ModelPrewarmRequest(request: ModelRequest(), promptPrefix: promptPrefix))
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
    try await respond(
      promptEntry: promptEntry,
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  private func respond<Content>(
    promptEntry: Transcript.Prompt? = nil,
    toolOutputs: [Transcript.ToolOutput] = [],
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<Content> where Content: Generable & Sendable {
    beginResponding()
    defer { endResponding() }

    let modelResponse = try await engine.respond(
      promptEntry: promptEntry,
      toolOutputs: toolOutputs,
      structuredOutput: Self.structuredOutputRequest(for: type, includeSchemaInPrompt: includeSchemaInPrompt),
      options: options,
    )
    await syncFromEngine()

    let rawContent = modelResponse.content ?? Self.emptyRawContent(for: type)
    let content = try Self.decode(rawContent, as: type)

    return Response(
      content: content,
      rawContent: rawContent,
      transcriptEntries: Self.responseTranscriptEntries(from: modelResponse),
      tokenUsage: modelResponse.tokenUsage,
      responseMetadata: modelResponse.responseMetadata,
    )
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
    streamResponse(
      promptEntry: promptEntry,
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
  }

  private func streamResponse<Content>(
    promptEntry: Transcript.Prompt? = nil,
    toolOutputs: [Transcript.ToolOutput] = [],
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    let relay = AsyncThrowingStream<ResponseStream<Content>.Snapshot, any Error> { continuation in
      Task {
        self.beginResponding()
        defer { self.endResponding() }

        do {
          let upstream = await self.engine.streamResponse(
            promptEntry: promptEntry,
            toolOutputs: toolOutputs,
            structuredOutput: Self.structuredOutputRequest(for: type, includeSchemaInPrompt: includeSchemaInPrompt),
            options: options,
          )
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
            await self.syncFromEngine()
            let content = Self.partialContent(from: snapshot.rawContent, as: type)
            let derived = ResponseStream<Content>.Snapshot(
              content: content,
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

          if let pendingSnapshot {
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

  /// Runs one raw model turn for higher-level runtime code built on this session.
  package func modelResponseForRuntime(
    promptEntry: Transcript.Prompt? = nil,
    toolOutputs: [Transcript.ToolOutput] = [],
    structuredOutput: StructuredOutputRequest? = nil,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> ModelResponse {
    beginResponding()
    defer { endResponding() }

    let response = try await engine.respond(
      promptEntry: promptEntry,
      toolOutputs: toolOutputs,
      structuredOutput: structuredOutput,
      options: options,
    )
    await syncFromEngine()
    return response
  }

  /// Streams one raw model turn for higher-level runtime code built on this session.
  package func modelStreamForRuntime(
    promptEntry: Transcript.Prompt? = nil,
    toolOutputs: [Transcript.ToolOutput] = [],
    structuredOutput: StructuredOutputRequest? = nil,
    options: GenerationOptions = GenerationOptions(),
  ) -> AsyncThrowingStream<ConversationStreamSnapshot, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        beginResponding()
        defer { endResponding() }

        do {
          let upstream = await engine.streamResponse(
            promptEntry: promptEntry,
            toolOutputs: toolOutputs,
            structuredOutput: structuredOutput,
            options: options,
          )
          for try await snapshot in upstream {
            await syncFromEngine()
            continuation.yield(snapshot)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Applies already-produced transcript entries for runtime-owned tool execution helpers.
  package func applyRuntimeResponse(_ response: ModelResponse) async {
    await engine.apply(response)
    await syncFromEngine()
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

  /// Appends tool outputs and generates one complete follow-up response without executing additional tools.
  @discardableResult
  public func respond(
    with toolOutputs: [Transcript.ToolOutput],
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<String> {
    try await respond(with: toolOutputs, generating: String.self, includeSchemaInPrompt: true, options: options)
  }

  /// Appends tool outputs and generates one complete structured follow-up response without executing additional tools.
  @discardableResult
  public func respond<Content>(
    with toolOutputs: [Transcript.ToolOutput],
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) async throws -> Response<Content> where Content: Generable & Sendable {
    try await respond(
      toolOutputs: toolOutputs,
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
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

  /// Appends tool outputs and streams one follow-up response without executing additional tools.
  public func streamResponse(
    with toolOutputs: [Transcript.ToolOutput],
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<String> {
    streamResponse(with: toolOutputs, generating: String.self, includeSchemaInPrompt: true, options: options)
  }

  /// Appends tool outputs and streams one structured follow-up response without executing additional tools.
  public func streamResponse<Content>(
    with toolOutputs: [Transcript.ToolOutput],
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    streamResponse(
      toolOutputs: toolOutputs,
      generating: type,
      includeSchemaInPrompt: includeSchemaInPrompt,
      options: options,
    )
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
    model.logFeedbackAttachment(FeedbackAttachmentRequest(
      transcript: transcript,
      sentiment: sentiment,
      issues: issues,
      desiredOutput: desiredOutput,
      responseMetadata: responseMetadata,
    ))
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
  ) async throws -> Response<String> where SessionSchema: TranscriptSchema & GroundingSupportingSchema {
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
    where SessionSchema: TranscriptSchema & GroundingSupportingSchema,
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
    where SessionSchema: TranscriptSchema & GroundingSupportingSchema,
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
  ) throws -> sending ResponseStream<String> where SessionSchema: TranscriptSchema & GroundingSupportingSchema {
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
    where SessionSchema: TranscriptSchema & GroundingSupportingSchema,
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
    where SessionSchema: TranscriptSchema & GroundingSupportingSchema,
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
  static func structuredOutputRequest<Content>(
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

  static func decode<Content>(_ rawContent: GeneratedContent, as type: Content.Type) throws -> Content where Content: Generable {
    if type == String.self {
      if case let .string(text) = rawContent.kind {
        return text as! Content
      }
      return rawContent.jsonString as! Content
    }
    return try Content(rawContent)
  }

  static func emptyRawContent<Content>(for type: Content.Type) -> GeneratedContent where Content: Generable {
    if type == String.self {
      return GeneratedContent("")
    }
    return GeneratedContent(properties: [:])
  }

  static func responseTranscriptEntries(from response: ModelResponse) -> [Transcript.Entry] {
    var entries = response.transcriptEntries
    entries.append(contentsOf: response.reasoning.map(Transcript.Entry.reasoning))
    if response.toolCalls.isEmpty == false {
      entries.append(.toolCalls(.init(calls: response.toolCalls.map(\.call))))
    }
    return entries
  }

  static func partialContent<Content>(
    from rawContent: GeneratedContent?,
    as type: Content.Type,
  ) -> Content.PartiallyGenerated? where Content: Generable {
    guard let rawContent else { return nil }
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

  func syncFromEngine() async {
    let transcript = await engine.transcript
    let tokenUsage = await engine.tokenUsage
    let responseMetadata = await engine.responseMetadata
    withMutation(keyPath: \.transcript) {
      state.withLock {
        $0.transcript = transcript
        $0.tokenUsage = tokenUsage
        $0.responseMetadata = responseMetadata
      }
    }
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
  ) throws -> Transcript.Prompt where SessionSchema: TranscriptSchema & GroundingSupportingSchema {
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
