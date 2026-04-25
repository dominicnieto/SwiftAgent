// By Dennis Müller

import AnthropicSession
import SwiftAgent

enum AnthropicStreamingToolCallsWeatherScenario {
  /// Matches: `Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingToolCallsTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "anthropic/streaming-tool-calls/weather",
    provider: .anthropic,
    unitTestFile: "Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingToolCallsTests.swift",
    expectedRecordedResponsesCount: 2,
    run: { recorder, secrets in
      let configuration = try AnthropicConfiguration.recording(
        apiKey: secrets.anthropicAPIKey(),
        recorder: recorder,
      )

      let session = AnthropicSession(
        tools: WeatherTool(),
        instructions: """
        Do not write any text before the tool call.
        Call `get_weather` exactly once with:
        { "location": "Tokyo", "requestedDate": "2026-01-15", "timeOfDay": "afternoon" }
        After tool output, reply with exactly: Done.
        """,
        configuration: configuration,
      )

      let stream = try session.streamResponse(
        to: "Weather update",
        using: AnthropicRecordingModel.model,
      )

      for try await _ in stream {}
    },
  )
}

private struct WeatherTool: SwiftAgent.Tool {
  var name: String = "get_weather"
  var description: String = "Get current weather for a given location."

  @Generable
  struct Arguments {
    var location: String
    var requestedDate: String
    var timeOfDay: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}
