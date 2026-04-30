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
}

/// Error used when a model omits the neutral turn contract.
public enum LanguageModelContractError: Error, LocalizedError, Sendable, Equatable {
  case neutralTurnNotImplemented(modelType: String)

  public var errorDescription: String? {
    switch self {
    case let .neutralTurnNotImplemented(modelType):
      "\(modelType) has not implemented the neutral model-turn API."
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
}

public extension LanguageModel where UnavailableReason == Never {
  /// Models with `Never` as their unavailable reason are always available.
  var availability: Availability<UnavailableReason> {
    .available
  }
}
