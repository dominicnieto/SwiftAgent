// By Dennis Müller

import Foundation
import SwiftAgent
import SwiftAnthropic

/// The model to use for generating a response.
public enum AnthropicModel: Equatable, Hashable, Sendable, AdapterModel {
  case claudeOpus45
  case claudeSonnet45
  case claudeHaiku45
  case claude3Opus
  case claude3Sonnet
  case claude3Haiku
  case claude35SonnetLatest
  case claude35HaikuLatest
  case claude37SonnetLatest
  case other(String)

  public var rawValue: String {
    switch self {
    case .claudeOpus45:
      "claude-opus-4-5"
    case .claudeSonnet45:
      "claude-sonnet-4-5"
    case .claudeHaiku45:
      "claude-haiku-4-5"
    case .claude3Opus:
      Model.claude3Opus.value
    case .claude3Sonnet:
      Model.claude3Sonnet.value
    case .claude3Haiku:
      Model.claude3Haiku.value
    case .claude35SonnetLatest:
      Model.claude35Sonnet.value
    case .claude35HaikuLatest:
      Model.claude35Haiku.value
    case .claude37SonnetLatest:
      Model.claude37Sonnet.value
    case let .other(value):
      value
    }
  }

  public static let `default`: AnthropicModel = .claudeSonnet45
}
