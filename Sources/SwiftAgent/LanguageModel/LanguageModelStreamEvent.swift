import Foundation

/// A normalized warning emitted by a provider or the main session.
public struct LanguageModelWarning: Sendable, Equatable {
  public var code: String
  public var message: String
  public var providerMetadata: [String: JSONValue]

  public init(code: String, message: String, providerMetadata: [String: JSONValue] = [:]) {
    self.code = code
    self.message = message
    self.providerMetadata = providerMetadata
  }
}

/// Rate-limit information normalized from provider response metadata.
public struct RateLimitState: Sendable, Equatable {
  public var limit: Int?
  public var remaining: Int?
  public var resetAt: Date?
  public var retryAfter: TimeInterval?

  public init(limit: Int? = nil, remaining: Int? = nil, resetAt: Date? = nil, retryAfter: TimeInterval? = nil) {
    self.limit = limit
    self.remaining = remaining
    self.resetAt = resetAt
    self.retryAfter = retryAfter
  }
}

/// Metadata reported for a provider response or stream.
public struct ResponseMetadata: Sendable, Equatable {
  public var id: String?
  public var requestID: UUID?
  public var providerRequestID: String?
  public var providerName: String?
  public var modelID: String?
  public var timestamp: Date?
  public var rateLimits: [String: RateLimitState]
  public var warnings: [LanguageModelWarning]
  public var providerMetadata: [String: JSONValue]

  public init(
    id: String? = nil,
    requestID: UUID? = nil,
    providerRequestID: String? = nil,
    providerName: String? = nil,
    modelID: String? = nil,
    timestamp: Date? = nil,
    rateLimits: [String: RateLimitState] = [:],
    warnings: [LanguageModelWarning] = [],
    providerMetadata: [String: JSONValue] = [:],
  ) {
    self.id = id
    self.requestID = requestID
    self.providerRequestID = providerRequestID
    self.providerName = providerName
    self.modelID = modelID
    self.timestamp = timestamp
    self.rateLimits = rateLimits
    self.warnings = warnings
    self.providerMetadata = providerMetadata
  }
}

public extension ResponseMetadata {
  /// Returns metadata formed by using non-empty values from `other` over this value.
  func merging(_ other: ResponseMetadata) -> ResponseMetadata {
    ResponseMetadata(
      id: other.id ?? id,
      requestID: other.requestID ?? requestID,
      providerRequestID: other.providerRequestID ?? providerRequestID,
      providerName: other.providerName ?? providerName,
      modelID: other.modelID ?? modelID,
      timestamp: other.timestamp ?? timestamp,
      rateLimits: rateLimits.merging(other.rateLimits) { _, new in new },
      warnings: warnings + other.warnings,
      providerMetadata: providerMetadata.merging(other.providerMetadata) { _, new in new },
    )
  }
}

/// Normalized reason a provider finished a generation.
public enum FinishReason: Sendable, Equatable {
  case completed
  case length
  case contentFilter
  case toolCalls
  case stopSequence
  case cancelled
  case failed
  case unknown(String)
}

/// A normalized streaming failure with provider metadata preserved outside the transcript.
public struct LanguageModelStreamError: Error, LocalizedError, Sendable, Equatable {
  public var code: String
  public var message: String
  public var providerMetadata: [String: JSONValue]

  public init(code: String, message: String, providerMetadata: [String: JSONValue] = [:]) {
    self.code = code
    self.message = message
    self.providerMetadata = providerMetadata
  }

  public var errorDescription: String? {
    message
  }
}

/// Rich provider-originated stream events that the main session reduces into transcript and usage state.
public enum LanguageModelStreamEvent: Sendable, Equatable {
  case streamStarted(warnings: [LanguageModelWarning])

  case textStart(id: String)
  case textDelta(id: String, delta: String)
  case textEnd(id: String)

  case structuredStart(id: String, typeName: String)
  case structuredDelta(id: String, delta: GeneratedContent)
  case structuredEnd(id: String)

  case reasoningStart(id: String)
  case reasoningDelta(id: String, delta: String)
  case reasoningEnd(id: String, encryptedReasoning: String?)

  case toolInputStart(id: String, callId: String?, toolName: String)
  case toolInputDelta(id: String, delta: String)
  case toolInputEnd(id: String, arguments: GeneratedContent?)
  case toolCall(Transcript.ToolCall)
  case toolResult(Transcript.ToolOutput)

  case responseMetadata(ResponseMetadata)
  case usage(TokenUsage)
  case finished(FinishReason)
  case raw(JSONValue)
  case failed(LanguageModelStreamError)
}

/// Updates produced after reducing provider stream events through SwiftAgent session state.
public enum LanguageModelUpdate: Sendable, Equatable {
  case transcript(Transcript.Entry)
  case tokenUsage(TokenUsage)
  case metadata(ResponseMetadata)
  case warning(LanguageModelWarning)
}
