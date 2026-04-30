import Foundation

/// Normalized capabilities for a language model, its provider API, and its runtime backend.
public struct LanguageModelCapabilities: Sendable, Equatable {
  /// Capabilities of the selected model identifier.
  public var model: ModelCapabilities

  /// Capabilities of the provider/API path used to access the model.
  public var provider: ProviderCapabilities

  /// Capabilities of a local runtime backend, when applicable.
  public var runtime: RuntimeCapabilities?

  public init(
    model: ModelCapabilities = ModelCapabilities(),
    provider: ProviderCapabilities = [],
    runtime: RuntimeCapabilities? = nil,
  ) {
    self.model = model
    self.provider = provider
    self.runtime = runtime
  }
}

/// Capabilities tied to a specific model identifier.
public struct ModelCapabilities: Sendable, Equatable {
  public var supportsTextGeneration: Bool
  public var supportsImageInput: Bool
  public var supportsAudioInput: Bool
  public var supportsEmbeddings: Bool
  public var supportsReasoning: Bool
  public var contextWindowTokens: Int?
  public var maximumOutputTokens: Int?
  public var architecture: String?

  public init(
    supportsTextGeneration: Bool = true,
    supportsImageInput: Bool = false,
    supportsAudioInput: Bool = false,
    supportsEmbeddings: Bool = false,
    supportsReasoning: Bool = false,
    contextWindowTokens: Int? = nil,
    maximumOutputTokens: Int? = nil,
    architecture: String? = nil,
  ) {
    self.supportsTextGeneration = supportsTextGeneration
    self.supportsImageInput = supportsImageInput
    self.supportsAudioInput = supportsAudioInput
    self.supportsEmbeddings = supportsEmbeddings
    self.supportsReasoning = supportsReasoning
    self.contextWindowTokens = contextWindowTokens
    self.maximumOutputTokens = maximumOutputTokens
    self.architecture = architecture
  }
}

/// Common provider/API capabilities used for validation, fallback, tests, and UI affordances.
public struct ProviderCapabilities: OptionSet, Sendable, Hashable {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static let textStreaming = Self(rawValue: 1 << 0)
  public static let structuredOutputs = Self(rawValue: 1 << 1)
  public static let structuredStreaming = Self(rawValue: 1 << 2)
  public static let toolCalling = Self(rawValue: 1 << 3)
  public static let toolCallStreaming = Self(rawValue: 1 << 4)
  public static let parallelToolCalls = Self(rawValue: 1 << 5)
  public static let imageInput = Self(rawValue: 1 << 6)
  public static let reasoningSummaries = Self(rawValue: 1 << 7)
  public static let encryptedReasoningContinuity = Self(rawValue: 1 << 8)
  public static let tokenUsage = Self(rawValue: 1 << 9)
  public static let streamingTokenUsage = Self(rawValue: 1 << 10)
  public static let responseContinuation = Self(rawValue: 1 << 11)
}

/// Capabilities tied to a local inference backend.
public struct RuntimeCapabilities: Sendable, Equatable {
  public var supportsKVQuantization: Bool
  public var supportsSpeculativeDecoding: Bool
  public var supportsIncrementalPrefill: Bool
  public var supportsModelCache: Bool
  public var unavailableReasons: [String: String]

  public init(
    supportsKVQuantization: Bool = false,
    supportsSpeculativeDecoding: Bool = false,
    supportsIncrementalPrefill: Bool = false,
    supportsModelCache: Bool = false,
    unavailableReasons: [String: String] = [:],
  ) {
    self.supportsKVQuantization = supportsKVQuantization
    self.supportsSpeculativeDecoding = supportsSpeculativeDecoding
    self.supportsIncrementalPrefill = supportsIncrementalPrefill
    self.supportsModelCache = supportsModelCache
    self.unavailableReasons = unavailableReasons
  }
}

/// A model can conform when it reports capabilities explicitly.
public protocol CapabilityReportingLanguageModel: LanguageModel {
  var capabilities: LanguageModelCapabilities { get }
}

/// Marker protocol for providers that stream provider turn events.
public protocol EventStreamingLanguageModel: LanguageModel {}

/// Marker protocol for providers that can stream tool-call argument deltas.
public protocol StreamingToolCallLanguageModel: EventStreamingLanguageModel {}

/// Marker protocol for providers that support provider-native structured outputs.
public protocol StructuredOutputLanguageModel: LanguageModel {}

public extension ProviderCapabilities {
  /// Infers capability flags that are proven by protocol conformance.
  static func inferred(from model: any LanguageModel) -> Self {
    var capabilities: Self = []

    if model is any EventStreamingLanguageModel {
      capabilities.insert(.textStreaming)
    }
    if model is any StreamingToolCallLanguageModel {
      capabilities.insert(.toolCallStreaming)
    }
    if model is any StructuredOutputLanguageModel {
      capabilities.insert(.structuredOutputs)
    }

    return capabilities
  }
}

public extension LanguageModelCapabilities {
  /// Builds a baseline capability value using protocol inference.
  static func inferred(from model: any LanguageModel) -> Self {
    LanguageModelCapabilities(provider: .inferred(from: model))
  }
}
