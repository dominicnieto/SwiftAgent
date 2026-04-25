// By Dennis Müller

import OpenAISession
import SwiftAgent

enum OpenAIToolCallsWeatherScenario {
  /// Matches: `Tests/SwiftAgentTests/OpenAISession/OpenAIToolCallsTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "openai/tool-calls/weather",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/OpenAISession/OpenAIToolCallsTests.swift",
    expectedRecordedResponsesCount: 2,
    run: { recorder, secrets in
      let configuration = try OpenAIConfiguration.recording(
        apiKey: secrets.openAIAPIKey(),
        recorder: recorder,
      )

      let session = OpenAISession(
        schema: RecordingSchema(),
        instructions: """
        Always call `get_weather` exactly once before answering.
        Call it with exactly: { "location": "New York City, USA" }.
        After tool output, reply with exactly: Done.
        """,
        configuration: configuration,
      )

      _ = try await session.respond(
        to: "What is the weather in New York City, USA?",
        using: .gpt4o,
      )
    },
  )
}

@SessionSchema
private struct RecordingSchema {
  @Tool var weather = WeatherTool()
}

private struct WeatherTool: SwiftAgent.Tool {
  var name: String = "get_weather"
  var description: String = "Get current temperature for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}
