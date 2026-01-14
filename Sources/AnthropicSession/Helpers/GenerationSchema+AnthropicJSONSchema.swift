// By Dennis Müller

import Foundation
import FoundationModels
import SwiftAnthropic

extension JSONSchema {
  /// Convenience: build a `JSONSchema` from *any* `Encodable` payload by round-tripping
  /// through `Data` (no intermediate `String` allocation).
  static func fromEncodable(
    _ value: some Encodable,
    encoder: JSONEncoder? = nil,
    decoder: JSONDecoder? = nil,
  ) throws -> JSONSchema {
    let encoder = encoder ?? makeSchemaEncoder()
    let decoder = decoder ?? makeSchemaDecoder()
    let data = try encoder.encode(value)
    return try decoder.decode(JSONSchema.self, from: data)
  }
}

/// FoundationModels glue
extension GenerationSchema {
  /// Convert a `GenerationSchema` (from FoundationModels) into an Anthropic `JSONSchema`.
  func asAnthropicJSONSchema(
    encoder: JSONEncoder? = nil,
    decoder: JSONDecoder? = nil,
  ) throws -> JSONSchema {
    let encoder = encoder ?? makeSchemaEncoder()
    let decoder = decoder ?? makeSchemaDecoder()
    let data = try encoder.encode(self)
    return try decoder.decode(JSONSchema.self, from: data)
  }
}

@inline(__always)
private func makeSchemaEncoder() -> JSONEncoder {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  encoder.dateEncodingStrategy = .iso8601
  return encoder
}

@inline(__always)
private func makeSchemaDecoder() -> JSONDecoder {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  return decoder
}
