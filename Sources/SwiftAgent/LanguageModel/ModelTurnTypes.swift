import Foundation

/// A provider-neutral request for a single model turn.
public struct ModelRequest: Sendable, Equatable, Codable {
  /// Conversation messages already reduced into provider-neutral form.
  public var messages: [ModelMessage]
  /// Developer instructions that apply to the turn.
  public var instructions: Instructions?
  /// Tools that the provider may expose to the model for this turn.
  public var tools: [ToolDefinition]
  /// Provider-neutral tool selection policy.
  public var toolChoice: ToolChoice?
  /// Structured output request policy for this turn.
  public var structuredOutput: StructuredOutputRequest?
  /// Sampling, limits, streaming cadence, and provider-specific options.
  public var generationOptions: GenerationOptions
  /// Binary or URL-backed attachments that should be serialized by the provider.
  public var attachments: [ModelAttachment]

  public init(
    messages: [ModelMessage] = [],
    instructions: Instructions? = nil,
    tools: [ToolDefinition] = [],
    toolChoice: ToolChoice? = nil,
    structuredOutput: StructuredOutputRequest? = nil,
    generationOptions: GenerationOptions = GenerationOptions(),
    attachments: [ModelAttachment] = [],
  ) {
    self.messages = messages
    self.instructions = instructions
    self.tools = tools
    self.toolChoice = toolChoice
    self.structuredOutput = structuredOutput
    self.generationOptions = generationOptions
    self.attachments = attachments
  }
}

/// A provider-neutral message in a model request.
public struct ModelMessage: Sendable, Equatable, Codable {
  /// The message role the provider should map to its wire format.
  public var role: ModelMessageRole
  /// Content segments for the message.
  public var segments: [Transcript.Segment]
  /// Provider-specific metadata preserved for later provider request reconstruction.
  public var providerMetadata: [String: JSONValue]

  public init(
    role: ModelMessageRole,
    segments: [Transcript.Segment],
    providerMetadata: [String: JSONValue] = [:],
  ) {
    self.role = role
    self.segments = segments
    self.providerMetadata = providerMetadata
  }
}

/// Provider-neutral message roles used when building model requests.
public enum ModelMessageRole: Sendable, Equatable, Codable {
  case system
  case user
  case assistant
  case tool
  case providerDefined(String)
}

/// An attachment that providers serialize into their native request formats.
public struct ModelAttachment: Sendable, Equatable, Codable, Identifiable {
  /// Stable attachment identifier.
  public var id: String
  /// The high-level attachment kind.
  public var kind: ModelAttachmentKind
  /// MIME type when known.
  public var mimeType: String?
  /// Inline attachment bytes when available.
  public var data: Data?
  /// Remote attachment URL when available.
  public var url: URL?
  /// Provider-specific metadata that should not be projected into the transcript.
  public var providerMetadata: [String: JSONValue]

  public init(
    id: String = UUID().uuidString,
    kind: ModelAttachmentKind,
    mimeType: String? = nil,
    data: Data? = nil,
    url: URL? = nil,
    providerMetadata: [String: JSONValue] = [:],
  ) {
    self.id = id
    self.kind = kind
    self.mimeType = mimeType
    self.data = data
    self.url = url
    self.providerMetadata = providerMetadata
  }
}

/// High-level attachment categories.
public enum ModelAttachmentKind: Sendable, Equatable, Codable {
  case image
  case audio
  case file
  case providerDefined(String)
}

/// Provider-neutral tool selection policy.
public enum ToolChoice: Sendable, Equatable, Codable {
  case automatic
  case none
  case required
  case named(String)
}

/// A provider-neutral tool definition.
public struct ToolDefinition: Sendable, Equatable, Codable, Identifiable {
  /// Stable identifier derived from the tool name.
  public var id: String { name }
  /// Tool name exposed to the model.
  public var name: String
  /// Natural-language description of the tool.
  public var description: String?
  /// JSON-compatible schema for tool arguments.
  public var schema: GenerationSchema
  /// Whether SwiftAgent or the provider executes this tool.
  public var kind: ToolDefinitionKind
  /// Provider-specific serialization metadata.
  public var providerMetadata: JSONValue?

  public init(
    name: String,
    description: String? = nil,
    schema: GenerationSchema,
    kind: ToolDefinitionKind = .local,
    providerMetadata: JSONValue? = nil,
  ) {
    self.name = name
    self.description = description
    self.schema = schema
    self.kind = kind
    self.providerMetadata = providerMetadata
  }

  public init(tool: any Tool, providerMetadata: JSONValue? = nil) {
    self.init(
      name: tool.name,
      description: tool.description,
      schema: tool.parameters,
      kind: .local,
      providerMetadata: providerMetadata,
    )
  }
}

/// Identifies who executes a tool definition.
public enum ToolDefinitionKind: Sendable, Equatable, Codable {
  case local
  case providerDefined
}

/// Structured output request policy for a model turn.
///
/// `includeSchemaInPrompt` lets the request builder preserve the existing
/// schema-in-prompt behavior before providers serialize the neutral request.
public struct StructuredOutputRequest: Sendable, Equatable, Codable {
  /// Provider-native or generated-content response format.
  public var format: ResponseFormat
  /// Whether the schema should also be injected into prompt text.
  public var includeSchemaInPrompt: Bool

  public init(format: ResponseFormat, includeSchemaInPrompt: Bool = true) {
    self.format = format
    self.includeSchemaInPrompt = includeSchemaInPrompt
  }
}

/// Structured output response format for a model turn.
public enum ResponseFormat: Sendable, Equatable, Codable {
  case text
  case jsonSchema(name: String?, schema: GenerationSchema, strict: Bool)
  case generatedContent(typeName: String, schema: GenerationSchema, strict: Bool)
}

/// A completed model-emitted tool call with execution ownership metadata.
public struct ModelToolCall: Sendable, Equatable, Codable, Identifiable {
  /// Stable identifier derived from the transcript tool call.
  public var id: String { call.id }
  /// Provider-neutral transcript representation of the tool call.
  public var call: Transcript.ToolCall
  /// Whether SwiftAgent or the provider owns execution of this tool call.
  public var kind: ToolDefinitionKind
  /// Provider-specific metadata preserved for diagnostics and continuation handling.
  public var providerMetadata: [String: JSONValue]

  public init(
    call: Transcript.ToolCall,
    kind: ToolDefinitionKind = .local,
    providerMetadata: [String: JSONValue] = [:],
  ) {
    var storedCall = call
    if storedCall.providerMetadata.isEmpty, providerMetadata.isEmpty == false {
      storedCall.providerMetadata = providerMetadata
    }
    self.call = storedCall
    self.kind = kind
    self.providerMetadata = providerMetadata
  }
}

/// A provider-neutral response for a single model turn.
public struct ModelResponse: Sendable, Equatable, Codable {
  /// Final generated content when the turn produced model output.
  public var content: GeneratedContent?
  /// Transcript entries the provider parsed directly from the turn.
  public var transcriptEntries: [Transcript.Entry]
  /// Completed tool calls requested by the model, including execution ownership.
  public var toolCalls: [ModelToolCall]
  /// Provider reasoning summaries parsed from the turn.
  public var reasoning: [Transcript.Reasoning]
  /// Normalized reason the provider stopped the turn.
  public var finishReason: FinishReason
  /// Token usage reported for this turn.
  public var tokenUsage: TokenUsage?
  /// Provider metadata reported for this turn.
  public var responseMetadata: ResponseMetadata?
  /// Raw provider output for diagnostics and tests.
  public var rawProviderOutput: JSONValue?

  public init(
    content: GeneratedContent? = nil,
    transcriptEntries: [Transcript.Entry] = [],
    toolCalls: [ModelToolCall] = [],
    reasoning: [Transcript.Reasoning] = [],
    finishReason: FinishReason,
    tokenUsage: TokenUsage? = nil,
    responseMetadata: ResponseMetadata? = nil,
    rawProviderOutput: JSONValue? = nil,
  ) {
    self.content = content
    self.transcriptEntries = transcriptEntries
    self.toolCalls = toolCalls
    self.reasoning = reasoning
    self.finishReason = finishReason
    self.tokenUsage = tokenUsage
    self.responseMetadata = responseMetadata
    self.rawProviderOutput = rawProviderOutput
  }
}

/// Completion metadata for a model stream.
public struct ModelTurnCompletion: Sendable, Equatable, Codable {
  /// Normalized finish reason.
  public var finishReason: FinishReason

  public init(finishReason: FinishReason) {
    self.finishReason = finishReason
  }
}

/// Request information a provider can use to prepare for an upcoming model turn.
public struct ModelPrewarmRequest: Sendable {
  /// The turn request being prepared.
  public var request: ModelRequest
  /// Optional prompt prefix retained for compatibility with current prewarm callers.
  public var promptPrefix: Prompt?

  public init(request: ModelRequest, promptPrefix: Prompt? = nil) {
    self.request = request
    self.promptPrefix = promptPrefix
  }
}

/// Provider feedback payload independent of a live session object.
public struct FeedbackAttachmentRequest: Sendable, Equatable {
  /// Transcript associated with the feedback.
  public var transcript: Transcript
  /// Optional user sentiment.
  public var sentiment: LanguageModelFeedback.Sentiment?
  /// Issues reported for the response.
  public var issues: [LanguageModelFeedback.Issue]
  /// Desired output supplied by the user, if any.
  public var desiredOutput: Transcript.Entry?
  /// Latest provider metadata associated with the response.
  public var responseMetadata: ResponseMetadata?

  public init(
    transcript: Transcript,
    sentiment: LanguageModelFeedback.Sentiment? = nil,
    issues: [LanguageModelFeedback.Issue] = [],
    desiredOutput: Transcript.Entry? = nil,
    responseMetadata: ResponseMetadata? = nil,
  ) {
    self.transcript = transcript
    self.sentiment = sentiment
    self.issues = issues
    self.desiredOutput = desiredOutput
    self.responseMetadata = responseMetadata
  }
}
