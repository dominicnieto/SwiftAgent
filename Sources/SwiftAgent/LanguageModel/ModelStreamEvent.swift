/// A normalized warning emitted by a provider or runtime component.
public typealias ModelWarning = LanguageModelWarning

/// Rich provider-originated stream events for one model turn.
public enum ModelStreamEvent: Sendable, Equatable {
  case started(ResponseMetadata?)
  case warnings([ModelWarning])
  case textStarted(id: String, metadata: ResponseMetadata?)
  case textDelta(id: String, delta: String)
  case textCompleted(id: String, metadata: ResponseMetadata?)
  case structuredDelta(id: String, delta: GeneratedContent)
  case reasoningStarted(id: String, metadata: ResponseMetadata?)
  case reasoningDelta(id: String, delta: String)
  case reasoningCompleted(Transcript.Reasoning)
  case toolInputStarted(ToolInputStart)
  case toolInputDelta(id: String, delta: String)
  case toolInputCompleted(id: String)
  case toolCallPartial(ToolCallPartial)
  case toolCallsCompleted([ModelToolCall], continuation: ProviderContinuation?)
  case providerToolResult(Transcript.ToolOutput)
  case source(ModelSource)
  case file(ModelFile)
  case usage(TokenUsage)
  case metadata(ResponseMetadata)
  case completed(ModelTurnCompletion)
  case failed(LanguageModelStreamError)
  case raw(JSONValue)
}

/// Metadata for the beginning of streamed tool input.
public struct ToolInputStart: Sendable, Equatable, Codable {
  /// Stable stream item identifier.
  public var id: String
  /// Provider correlation identifier for the tool call, if known.
  public var callId: String?
  /// Tool name emitted by the provider.
  public var toolName: String
  /// Whether SwiftAgent or the provider will execute this tool.
  public var kind: ToolDefinitionKind
  /// Provider-specific metadata for diagnostics.
  public var providerMetadata: [String: JSONValue]

  public init(
    id: String,
    callId: String? = nil,
    toolName: String,
    kind: ToolDefinitionKind = .local,
    providerMetadata: [String: JSONValue] = [:],
  ) {
    self.id = id
    self.callId = callId
    self.toolName = toolName
    self.kind = kind
    self.providerMetadata = providerMetadata
  }
}

/// A partially assembled tool call emitted while a provider streams input JSON.
public struct ToolCallPartial: Sendable, Equatable, Codable {
  /// Stable stream item identifier.
  public var id: String
  /// Provider correlation identifier for the tool call, if known.
  public var callId: String?
  /// Tool name emitted by the provider.
  public var toolName: String?
  /// Raw partial JSON arguments emitted so far.
  public var partialArguments: String
  /// Parsed arguments when the partial JSON can be decoded.
  public var arguments: GeneratedContent?
  /// Whether SwiftAgent or the provider will execute this tool.
  public var kind: ToolDefinitionKind

  public init(
    id: String,
    callId: String? = nil,
    toolName: String? = nil,
    partialArguments: String,
    arguments: GeneratedContent? = nil,
    kind: ToolDefinitionKind = .local,
  ) {
    self.id = id
    self.callId = callId
    self.toolName = toolName
    self.partialArguments = partialArguments
    self.arguments = arguments
    self.kind = kind
  }
}

/// A provider-reported source used by a model response.
public struct ModelSource: Sendable, Equatable, Codable, Identifiable {
  /// Stable source identifier.
  public var id: String
  /// Human-readable title, if available.
  public var title: String?
  /// Source URL, if available.
  public var url: String?
  /// Provider-specific metadata for diagnostics.
  public var providerMetadata: [String: JSONValue]

  public init(
    id: String,
    title: String? = nil,
    url: String? = nil,
    providerMetadata: [String: JSONValue] = [:],
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.providerMetadata = providerMetadata
  }
}

/// A provider-reported file produced or referenced during generation.
public struct ModelFile: Sendable, Equatable, Codable, Identifiable {
  /// Stable file identifier.
  public var id: String
  /// File name, if available.
  public var filename: String?
  /// MIME type, if available.
  public var mimeType: String?
  /// Remote file URL, if available.
  public var url: String?
  /// Provider-specific metadata for diagnostics.
  public var providerMetadata: [String: JSONValue]

  public init(
    id: String,
    filename: String? = nil,
    mimeType: String? = nil,
    url: String? = nil,
    providerMetadata: [String: JSONValue] = [:],
  ) {
    self.id = id
    self.filename = filename
    self.mimeType = mimeType
    self.url = url
    self.providerMetadata = providerMetadata
  }
}
