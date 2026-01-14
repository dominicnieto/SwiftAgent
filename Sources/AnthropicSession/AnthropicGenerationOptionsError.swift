// By Dennis Müller

import Foundation

public enum AnthropicGenerationOptionsError: Error, LocalizedError {
  case missingMaxTokens
  case invalidTemperature(Double)
  case invalidTopP(Double)
  case invalidTopK(Int)
  case invalidThinkingBudget(Int)

  public var errorDescription: String? {
    switch self {
    case .missingMaxTokens:
      "Anthropic requests require maxTokens to be set."
    case let .invalidTemperature(value):
      "Temperature must be between 0 and 1. Got: \(value)."
    case let .invalidTopP(value):
      "Top-p must be between 0 and 1. Got: \(value)."
    case let .invalidTopK(value):
      "Top-k must be greater than 0. Got: \(value)."
    case let .invalidThinkingBudget(value):
      "Thinking budget must be greater than 0. Got: \(value)."
    }
  }
}
