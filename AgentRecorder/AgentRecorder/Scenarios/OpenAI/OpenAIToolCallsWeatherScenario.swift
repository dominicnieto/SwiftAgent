// By Dennis Muller

import SwiftAgent

enum OpenAIToolCallsWeatherScenario {
  static let scenario = AgentRecorderScenario(
    id: "openai/tool-calls/weather",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/Providers/OpenAIProviderReplayTests.swift",
    expectedRecordedResponsesCount: 2,
    run: { recorder, secrets in
      let apiKey = try secrets.openAIAPIKey()
      let model = OpenAILanguageModel(
        apiKey: apiKey,
        model: "gpt-4o",
        apiVariant: .responses,
        httpClient: OpenAIRecordingHTTPClient.make(apiKey: apiKey, recorder: recorder),
      )
      let session = LanguageModelSession(
        model: model,
        tools: [WeatherTool()],
        instructions: """
        Always call `get_weather` exactly once before answering.
        Call it with exactly: { "location": "New York City, USA" }.
        After tool output, reply with exactly: Done.
        """,
      )

      _ = try await session.respond(to: "What is the weather in New York City, USA?")
    },
  )
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
