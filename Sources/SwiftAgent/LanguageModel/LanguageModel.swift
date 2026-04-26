import Foundation

/// A provider boundary capable of generating responses for a ``LanguageModelSession``.
public protocol LanguageModel: Sendable {
  /// The reason type this model reports when it is unavailable.
  associatedtype UnavailableReason: Sendable

  /// The custom generation options supported by this model.
  associatedtype CustomGenerationOptions: SwiftAgent.CustomGenerationOptions = Never

  /// Current model availability.
  var availability: Availability<UnavailableReason> { get }

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
  ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable

  /// Builds an attachment that can be sent to the provider's feedback endpoint.
  func logFeedbackAttachment(
    within session: LanguageModelSession,
    sentiment: LanguageModelFeedback.Sentiment?,
    issues: [LanguageModelFeedback.Issue],
    desiredOutput: Transcript.Entry?,
  ) -> Data
}

public extension LanguageModel {
  /// Whether this model is currently available.
  var isAvailable: Bool {
    if case .available = availability {
      return true
    }
    return false
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
