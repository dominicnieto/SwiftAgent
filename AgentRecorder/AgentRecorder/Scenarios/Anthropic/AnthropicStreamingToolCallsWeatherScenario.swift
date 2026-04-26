// By Dennis Muller

import SwiftAgent

enum AnthropicStreamingToolCallsWeatherScenario {
  static let scenario = AgentRecorderScenario(
    id: "anthropic/streaming-tool-calls/weather",
    provider: .anthropic,
    unitTestFile: "Tests/SwiftAgentTests/Core/DirectProviderReplayTests.swift",
    expectedRecordedResponsesCount: 2,
    run: { recorder, secrets in
      let apiKey = try secrets.anthropicAPIKey()
      let model = AnthropicLanguageModel(
        apiKey: apiKey,
        model: AnthropicRecordingModel.model,
        httpClient: AnthropicRecordingHTTPClient.make(apiKey: apiKey, recorder: recorder),
      )
      let session = LanguageModelSession(
        model: model,
        tools: [WeatherTool()],
        instructions: """
        Do not write any text before the tool call.
        Call `get_weather` exactly once with:
        { "location": "Tokyo", "requestedDate": "2026-01-15", "timeOfDay": "afternoon" }
        After tool output, reply with exactly: Done.
        """,
      )

      let stream = session.streamResponse(to: "Weather update")

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
