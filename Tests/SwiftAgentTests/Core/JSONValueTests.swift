import Foundation
import Testing

@testable import SwiftAgent

@Suite("JSONValue")
struct JSONValueTests {
  @Test func exposesJSONSchemaBackedValuesThroughSwiftAgent() throws {
    let value: JSONValue = .object([
      "name": .string("SwiftAgent"),
      "enabled": .bool(true),
      "count": .int(2),
      "temperature": .double(0.7),
      "tags": .array([.string("agent"), .string("provider")]),
    ])

    let encoded = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)

    #expect(decoded == value)
  }
}
