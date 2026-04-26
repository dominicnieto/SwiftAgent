import Foundation

/// Options that control how a language model generates a response.
public struct GenerationOptions: Sendable, Equatable, Codable {
  /// A strategy for sampling tokens from the model's probability distribution.
  public struct SamplingMode: Sendable, Equatable, Codable {
    enum Mode: Sendable, Equatable, Codable {
      case greedy
      case topK(Int, seed: UInt64?)
      case nucleus(Double, seed: UInt64?)
    }

    let mode: Mode

    /// A sampling mode that always chooses the most likely token.
    public static var greedy: SamplingMode {
      SamplingMode(mode: .greedy)
    }

    /// A sampling mode that chooses from the top `k` candidate tokens.
    public static func random(top k: Int, seed: UInt64? = nil) -> SamplingMode {
      SamplingMode(mode: .topK(k, seed: seed))
    }

    /// A sampling mode that chooses from candidates up to a cumulative probability threshold.
    public static func random(probabilityThreshold: Double, seed: UInt64? = nil) -> SamplingMode {
      SamplingMode(mode: .nucleus(probabilityThreshold, seed: seed))
    }
  }

  /// The sampling strategy to use for generated tokens.
  public var sampling: SamplingMode?

  /// Temperature controls how much the model may choose less likely tokens.
  public var temperature: Double?

  /// The maximum number of tokens the model may produce.
  public var maximumResponseTokens: Int?

  /// The minimum interval between UI-oriented streaming snapshots.
  public var minimumStreamingSnapshotInterval: Duration?

  private var customOptionsStorage: CustomOptionsStorage = .init()

  /// Accesses custom generation options for a specific language model type.
  public subscript<Model: LanguageModel>(
    custom modelType: Model.Type,
  ) -> Model.CustomGenerationOptions? {
    get {
      customOptionsStorage[Model.self]
    }
    set {
      customOptionsStorage[Model.self] = newValue
    }
  }

  /// Creates generation options that control token sampling and response limits.
  public init(
    sampling: SamplingMode? = nil,
    temperature: Double? = nil,
    maximumResponseTokens: Int? = nil,
    minimumStreamingSnapshotInterval: Duration? = nil,
  ) {
    self.sampling = sampling
    self.temperature = temperature
    self.maximumResponseTokens = maximumResponseTokens
    self.minimumStreamingSnapshotInterval = minimumStreamingSnapshotInterval
  }
}

/// A protocol for model-specific custom generation options.
public protocol CustomGenerationOptions: Equatable, Sendable {}

extension Never: CustomGenerationOptions {}

extension Dictionary: CustomGenerationOptions where Key == String, Value == JSONValue {}

private struct CustomOptionsStorage: Sendable, Equatable, Codable {
  private var storage: [ObjectIdentifier: AnyCustomOptions] = [:]

  init() {}

  subscript<Model: LanguageModel>(modelType: Model.Type) -> Model.CustomGenerationOptions? {
    get {
      guard let wrapper = storage[ObjectIdentifier(modelType)] else {
        return nil
      }
      return wrapper.value as? Model.CustomGenerationOptions
    }
    set {
      if let newValue {
        storage[ObjectIdentifier(modelType)] = AnyCustomOptions(newValue)
      } else {
        storage.removeValue(forKey: ObjectIdentifier(modelType))
      }
    }
  }

  static func == (lhs: CustomOptionsStorage, rhs: CustomOptionsStorage) -> Bool {
    guard lhs.storage.count == rhs.storage.count else { return false }

    for (key, lhsWrapper) in lhs.storage {
      guard let rhsWrapper = rhs.storage[key],
            lhsWrapper.isEqual(to: rhsWrapper)
      else {
        return false
      }
    }

    return true
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: TypeNameCodingKey.self)

    for (_, wrapper) in storage {
      if let encode = wrapper.encode {
        let key = TypeNameCodingKey(wrapper.typeName)
        let nestedEncoder = container.superEncoder(forKey: key)
        try encode(nestedEncoder)
      }
    }
  }

  init(from decoder: any Decoder) throws {
    _ = decoder
    storage = [:]
  }
}

private struct AnyCustomOptions: Sendable {
  let value: any CustomGenerationOptions
  let typeName: String
  let equals: @Sendable (any CustomGenerationOptions) -> Bool
  let encode: (@Sendable (any Encoder) throws -> Void)?

  init<T: CustomGenerationOptions>(_ value: T) {
    self.value = value
    typeName = String(reflecting: T.self)
    equals = { other in
      guard let typed = other as? T else {
        return false
      }
      return value == typed
    }

    if value is any Encodable {
      encode = { encoder in
        try (value as! any Encodable).encode(to: encoder)
      }
    } else {
      encode = nil
    }
  }

  func isEqual(to other: AnyCustomOptions) -> Bool {
    equals(other.value)
  }
}

private struct TypeNameCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }

  init(_ typeName: String) {
    stringValue = typeName
  }

  init?(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    nil
  }
}
