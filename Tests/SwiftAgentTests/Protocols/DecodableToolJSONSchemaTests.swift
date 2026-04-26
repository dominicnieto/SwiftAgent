// By Dennis Müller

import Foundation
@testable import SwiftAgent
import Testing

@SessionSchema
private struct ToolSchemaSession {
  @Tool var forecast = ForecastTool()
}

@Suite("DecodableTool JSON schema")
struct DecodableToolJSONSchemaTests {
  private let session = ToolSchemaSession()

  @Test("Encodes compact and pretty tool schemas")
  func encodesToolSchema() throws {
    let tool = try #require(session.tools.first)

    let compactSchema = tool.jsonSchema()
    let prettySchema = tool.jsonSchema(prettyPrinted: true)

    let expectedCompact = #"{"description":"Return forecast units for a city.","name":"forecast_weather","parameters":{"additionalProperties":false,"properties":{"city":{"type":"string"},"units":{"type":"string"}},"required":["city","units"],"title":"Arguments","type":"object","x-order":["city","units"]},"type":"function"}"#

    let expectedPretty = #"""
    {
      "description" : "Return forecast units for a city.",
      "name" : "forecast_weather",
      "parameters" : {
        "additionalProperties" : false,
        "properties" : {
          "city" : {
            "type" : "string"
          },
          "units" : {
            "type" : "string"
          }
        },
        "required" : [
          "city",
          "units"
        ],
        "title" : "Arguments",
        "type" : "object",
        "x-order" : [
          "city",
          "units"
        ]
      },
      "type" : "function"
    }
    """#

    #expect(compactSchema == expectedCompact)
    #expect(prettySchema == expectedPretty)
    #expect(compactSchema.contains("\n") == false)
    #expect(prettySchema.contains("\n"))
  }
}

// MARK: - Tool Fixtures

private struct ForecastTool: SwiftAgent.Tool {
  static let description: String = "Return forecast units for a city."

  var name: String = "forecast_weather"
  var description: String { Self.description }

  @Generable
  struct Arguments {
    var city: String
    var units: String
  }

  func call(arguments: Arguments) async throws -> String {
    "Forecast"
  }
}
