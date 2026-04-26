/// Feedback about a language model response.
public struct LanguageModelFeedback: Sendable {
  /// A sentiment regarding the model's response.
  public enum Sentiment: Sendable, CaseIterable, Equatable, Hashable {
    case positive
    case negative
    case neutral
  }

  /// An issue with a model response.
  public struct Issue: Sendable, Equatable, Hashable {
    /// Categories for model response issues.
    public enum Category: Sendable, CaseIterable, Equatable, Hashable {
      case unhelpful
      case tooVerbose
      case didNotFollowInstructions
      case incorrect
      case stereotypeOrBias
      case suggestiveOrSexual
      case vulgarOrOffensive
      case triggeredGuardrailUnexpectedly
    }

    /// The category of the issue.
    public let category: Category

    /// Optional explanation of the issue.
    public let explanation: String?

    /// Creates a response issue.
    public init(category: Category, explanation: String? = nil) {
      self.category = category
      self.explanation = explanation
    }
  }

  /// Overall response sentiment.
  public let sentiment: Sentiment

  /// Issues observed in the response.
  public let issues: [Issue]

  /// Creates model feedback.
  public init(sentiment: Sentiment, issues: [Issue]) {
    self.sentiment = sentiment
    self.issues = issues
  }
}
