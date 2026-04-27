import Foundation

/// A provider boundary capable of generating one provider turn at a time.
public protocol LanguageModel: Sendable {
  /// The reason type this model reports when it is unavailable.
  associatedtype UnavailableReason: Sendable

  /// The custom generation options supported by this model.
  associatedtype CustomGenerationOptions: SwiftAgent.CustomGenerationOptions = Never

  /// Current model availability.
  var availability: Availability<UnavailableReason> { get }

  /// Normalized model/provider/runtime capabilities used for validation, tests, and UI affordances.
  var capabilities: LanguageModelCapabilities { get }

  /// Generates one complete provider turn from a neutral request.
  func respond(to request: ModelRequest) async throws -> ModelResponse

  /// Streams one provider turn as neutral model events.
  func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error>

  /// Prepares the model for an upcoming neutral request when the provider supports prewarming.
  func prewarm(for request: ModelPrewarmRequest)

  /// Builds an attachment that can be sent to the provider's feedback endpoint.
  func logFeedbackAttachment(_ request: FeedbackAttachmentRequest) -> Data

  /// Prepares the model for an upcoming prompt prefix when the provider supports prewarming.
  func prewarm(for session: LanguageModelSession, promptPrefix: Prompt?)

  /// Generates one complete response.
  func respond<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) async throws -> LanguageModelSession.Response<Content> where Content: Generable & Sendable

  /// Streams a response as provider updates arrive.
  func streamResponse<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) -> sending LanguageModelSession.ResponseStream<Content>
    where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable

  /// Builds an attachment that can be sent to the provider's feedback endpoint.
  func logFeedbackAttachment(
    within session: LanguageModelSession,
    sentiment: LanguageModelFeedback.Sentiment?,
    issues: [LanguageModelFeedback.Issue],
    desiredOutput: Transcript.Entry?,
  ) -> Data
}

/// Error used by compatibility defaults while providers migrate to the neutral turn contract.
public enum LanguageModelContractError: Error, LocalizedError, Sendable, Equatable {
  case neutralTurnNotImplemented(modelType: String)
  case sessionTurnNotImplemented(modelType: String)

  public var errorDescription: String? {
    switch self {
    case let .neutralTurnNotImplemented(modelType):
      "\(modelType) has not implemented the neutral model-turn API."
    case let .sessionTurnNotImplemented(modelType):
      "\(modelType) has not implemented the legacy session-shaped API."
    }
  }
}

public extension LanguageModel {
  /// Whether this model is currently available.
  var isAvailable: Bool {
    if case .available = availability {
      return true
    }
    return false
  }

  /// Default capability inference from protocol conformance.
  var capabilities: LanguageModelCapabilities {
    .inferred(from: self)
  }

  /// Default neutral turn implementation used only until providers migrate.
  func respond(to request: ModelRequest) async throws -> ModelResponse {
    _ = request
    throw LanguageModelContractError.neutralTurnNotImplemented(modelType: String(reflecting: Self.self))
  }

  /// Default empty stream used only until providers migrate.
  func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
    _ = request
    return AsyncThrowingStream { continuation in
      continuation.finish(throwing: LanguageModelContractError.neutralTurnNotImplemented(
        modelType: String(reflecting: Self.self),
      ))
    }
  }

  /// Default no-op prewarm implementation for neutral requests.
  func prewarm(for request: ModelPrewarmRequest) {
    _ = request
  }

  /// Default empty feedback attachment implementation for neutral requests.
  func logFeedbackAttachment(_ request: FeedbackAttachmentRequest) -> Data {
    _ = request
    return Data()
  }

  /// Default no-op prewarm implementation.
  func prewarm(for session: LanguageModelSession, promptPrefix: Prompt? = nil) {
    _ = session
    _ = promptPrefix
  }

  /// Default empty feedback attachment implementation.
  func logFeedbackAttachment(
    within session: LanguageModelSession,
    sentiment: LanguageModelFeedback.Sentiment? = nil,
    issues: [LanguageModelFeedback.Issue] = [],
    desiredOutput: Transcript.Entry? = nil,
  ) -> Data {
    _ = session
    _ = sentiment
    _ = issues
    _ = desiredOutput
    return Data()
  }
}

public extension LanguageModel where UnavailableReason == Never {
  /// Models with `Never` as their unavailable reason are always available.
  var availability: Availability<UnavailableReason> {
    .available
  }
}
