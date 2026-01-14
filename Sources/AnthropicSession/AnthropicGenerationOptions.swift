// By Dennis Müller

import Foundation
import SwiftAgent
@preconcurrency import SwiftAnthropic

public struct AnthropicGenerationOptions: AdapterGenerationOptions {
  public typealias Model = AnthropicModel
  public typealias GenerationOptionsError = AnthropicGenerationOptionsError

  public static func automatic(for model: Model) -> AnthropicGenerationOptions {
    var options = AnthropicGenerationOptions()
    options.maxOutputTokens = 1024
    return options
  }

  /// The maximum number of tokens the model should generate.
  public var maxOutputTokens: Int?

  /// Custom stop sequences that halt generation.
  public var stopSequences: [String]?

  /// Controls randomness. Range: 0...1.
  public var temperature: Double?

  /// Nucleus sampling. Range: 0...1.
  public var topP: Double?

  /// Top-k sampling. Must be greater than 0.
  public var topK: Int?

  /// Tool selection configuration.
  public var toolChoice: MessageParameter.ToolChoice?

  /// Extended thinking configuration.
  public var thinking: MessageParameter.Thinking?

  /// Minimum time between emitted streaming snapshots.
  public var minimumStreamingSnapshotInterval: Duration?

  public init() {}

  public init(
    maxOutputTokens: Int? = nil,
    stopSequences: [String]? = nil,
    temperature: Double? = nil,
    topP: Double? = nil,
    topK: Int? = nil,
    toolChoice: MessageParameter.ToolChoice? = nil,
    thinking: MessageParameter.Thinking? = nil,
    minimumStreamingSnapshotInterval: Duration? = nil,
  ) {
    self.maxOutputTokens = maxOutputTokens
    self.stopSequences = stopSequences
    self.temperature = temperature
    self.topP = topP
    self.topK = topK
    self.toolChoice = toolChoice
    self.thinking = thinking
    self.minimumStreamingSnapshotInterval = minimumStreamingSnapshotInterval
  }

  public func validate(for model: Model) throws(AnthropicGenerationOptionsError) {
    if let maxOutputTokens, maxOutputTokens <= 0 {
      throw GenerationOptionsError.missingMaxTokens
    }

    if let temperature, !(0.0...1.0).contains(temperature) {
      throw GenerationOptionsError.invalidTemperature(temperature)
    }

    if let topP, !(0.0...1.0).contains(topP) {
      throw GenerationOptionsError.invalidTopP(topP)
    }

    if let topK, topK <= 0 {
      throw GenerationOptionsError.invalidTopK(topK)
    }

    if let thinking {
      _ = thinking
    }
  }
}
