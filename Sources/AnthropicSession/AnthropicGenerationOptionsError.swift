// By Dennis Müller

import Foundation

public enum AnthropicGenerationOptionsError: Error, LocalizedError {
  case missingMaxTokens
  case invalidTemperature(Double)
  case invalidTopP(Double)
  case invalidTopK(Int)
  case invalidThinkingBudget(Int)
  case thinkingIncompatibleWithTemperature
  case thinkingIncompatibleWithTopP
  case thinkingIncompatibleWithTopK
  case thinkingIncompatibleWithToolChoice(String)
  case thinkingIncompatibleWithStructuredOutput
  case thinkingBudgetExceedsMaxOutputTokens(budgetTokens: Int, maxOutputTokens: Int)

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
      "Thinking budget must be at least 1024. Got: \(value)."
    case .thinkingIncompatibleWithTemperature:
      "Extended thinking isn't compatible with modifying temperature."
    case .thinkingIncompatibleWithTopP:
      "Extended thinking isn't compatible with modifying top-p."
    case .thinkingIncompatibleWithTopK:
      "Extended thinking isn't compatible with modifying top-k."
    case let .thinkingIncompatibleWithToolChoice(type):
      "Extended thinking isn't compatible with tool choice: \(type)."
    case .thinkingIncompatibleWithStructuredOutput:
      "Extended thinking isn't compatible with structured output (requires forced tool use)."
    case let .thinkingBudgetExceedsMaxOutputTokens(budgetTokens, maxOutputTokens):
      "`max_tokens` must be greater than `thinking.budget_tokens`. Got max_tokens=\(maxOutputTokens), budget_tokens=\(budgetTokens)."
    }
  }
}
