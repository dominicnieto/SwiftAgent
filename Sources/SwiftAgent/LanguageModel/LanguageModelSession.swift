import Foundation

/// A canonical session that coordinates a language model, tools, instructions, transcript, and usage state.
public final class LanguageModelSession: @unchecked Sendable {
  private let model: any LanguageModel
  private let state: Locked<State>

  /// Tools available to the model during this session.
  public let tools: [any Tool]

  /// Instructions applied to each turn.
  public let instructions: Instructions?

  /// Whether this session is currently waiting on model output.
  public var isResponding: Bool {
    state.withLock { $0.isResponding }
  }

  /// The current transcript assembled by this session.
  public var transcript: Transcript {
    state.withLock { $0.transcript }
  }

  /// Cumulative token usage reported by the model during this session.
  public var tokenUsage: TokenUsage? {
    state.withLock { $0.tokenUsage }
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
    state = Locked(State(transcript: Self.initialTranscript(instructions: instructions, tools: tools)))
  }

  /// Creates a session with a model, tools, and string instructions.
  public convenience init(
    model: any LanguageModel,
    tools: [any Tool] = [],
    instructions: String,
  ) {
    self.init(model: model, tools: tools, instructions: Instructions(instructions))
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
    beginResponding()
    defer { endResponding() }

    appendPrompt(prompt)

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

    return response
  }

  /// Streams a response and derives each public snapshot from transcript and usage state.
  public func streamResponse<Content>(
    to prompt: Prompt,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions(),
  ) -> sending ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    appendPrompt(prompt)

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

          for try await snapshot in upstream {
            self.recordProviderEntries(snapshot.transcriptEntries)
            self.recordTokenUsage(snapshot.tokenUsage)

            if let rawContent = snapshot.rawContent {
              self.recordResponse(rawContent: rawContent, status: .inProgress)
            }

            let derived = ResponseStream<Content>.Snapshot(
              content: snapshot.content,
              rawContent: snapshot.rawContent,
              transcript: self.transcript,
              tokenUsage: self.tokenUsage,
              transcriptEntries: snapshot.transcriptEntries,
            )
            lastSnapshot = derived
            continuation.yield(derived)
          }

          if let rawContent = lastSnapshot?.rawContent {
            self.recordResponse(rawContent: rawContent, status: .completed)
            continuation.yield(ResponseStream<Content>.Snapshot(
              content: lastSnapshot?.content,
              rawContent: rawContent,
              transcript: self.transcript,
              tokenUsage: self.tokenUsage,
            ))
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

    /// Creates a complete response.
    public init(
      content: Content,
      rawContent: GeneratedContent,
      transcriptEntries: [Transcript.Entry] = [],
      tokenUsage: TokenUsage? = nil,
    ) {
      self.content = content
      self.rawContent = rawContent
      self.transcriptEntries = transcriptEntries
      self.tokenUsage = tokenUsage
    }
  }

  /// An async response stream.
  struct ResponseStream<Content>: Sendable where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    private let fallbackSnapshot: Snapshot?
    private let stream: AsyncThrowingStream<Snapshot, any Error>?

    /// Creates a stream with one already-complete snapshot.
    public init(content: Content, rawContent: GeneratedContent, tokenUsage: TokenUsage? = nil) {
      fallbackSnapshot = Snapshot(
        content: content.asPartiallyGenerated(),
        rawContent: rawContent,
        tokenUsage: tokenUsage,
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

      /// Provider-emitted transcript entries represented by this snapshot.
      public var transcriptEntries: [Transcript.Entry]

      /// Creates a stream snapshot.
      public init(
        content: Content.PartiallyGenerated? = nil,
        rawContent: GeneratedContent? = nil,
        transcript: Transcript = Transcript(),
        tokenUsage: TokenUsage? = nil,
        transcriptEntries: [Transcript.Entry] = [],
      ) {
        self.content = content
        self.rawContent = rawContent
        self.transcript = transcript
        self.tokenUsage = tokenUsage
        self.transcriptEntries = transcriptEntries
      }
    }
  }

  /// Errors produced by canonical model sessions.
  enum GenerationError: Error, LocalizedError {
    /// Context describing a generation failure.
    public struct Context: Sendable {
      public let debugDescription: String

      public init(debugDescription: String) {
        self.debugDescription = debugDescription
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
    )
  }
}

private extension LanguageModelSession {
  func beginResponding() {
    state.withLock { $0.responseDepth += 1 }
  }

  func endResponding() {
    state.withLock { $0.responseDepth = max(0, $0.responseDepth - 1) }
  }

  func appendPrompt(_ prompt: Prompt) {
    let promptEntry = Transcript.Entry.prompt(.init(
      input: prompt.description,
      sources: Data(),
      prompt: prompt.description,
    ))
    state.withLock { $0.transcript.entries.append(promptEntry) }
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

    state.withLock { state in
      for entry in entries {
        state.transcript.upsert(entry)
      }
    }
  }

  func recordResponse(rawContent: GeneratedContent, status: Transcript.Status) {
    let segment: Transcript.Segment

    if case .string(let text) = rawContent.kind {
      segment = .text(.init(id: State.responseSegmentID, content: text))
    } else {
      segment = .structure(.init(id: State.responseSegmentID, content: rawContent))
    }

    let entry = Transcript.Entry.response(.init(
      id: State.responseEntryID,
      segments: [segment],
      status: status,
    ))
    state.withLock { $0.transcript.upsert(entry) }
  }

  func recordTokenUsage(_ usage: TokenUsage?) {
    guard let usage else { return }

    state.withLock { state in
      if state.tokenUsage == nil {
        state.tokenUsage = usage
      } else {
        state.tokenUsage?.merge(usage)
      }
    }
  }
}

private struct State: Sendable {
  static let responseEntryID = "language-model-session-response"
  static let responseSegmentID = "language-model-session-response-segment"

  var transcript: Transcript
  var tokenUsage: TokenUsage?
  var responseDepth = 0

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
