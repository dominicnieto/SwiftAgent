// By Dennis Muller

import SwiftAgent

enum OpenAIStreamingToolCallsWeatherScenario {
  static let scenario = AgentRecorderScenario(
    id: "openai/streaming-tool-calls/weather",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/Providers/OpenAIProviderReplayTests.swift",
    expectedRecordedResponsesCount: 2,
    run: { recorder, secrets in
      let apiKey = try secrets.openAIAPIKey()
      let model = OpenAILanguageModel(
        apiKey: apiKey,
        model: OpenAIRecordingModel.model,
        apiVariant: .responses,
        httpClient: OpenAIRecordingHTTPClient.make(apiKey: apiKey, recorder: recorder),
      )
      let session = LanguageModelSession(
        model: model,
        tools: [WeatherTool()],
        instructions: """
        Always call `get_weather` exactly once before answering.
        After tool output, reply with exactly: Current weather in New York City, USA: Sunny.
        """,
      )

      var options = GenerationOptions()
      options[custom: OpenAILanguageModel.self] = .init(
        reasoning: .init(effort: .low, summary: "detailed"),
      )

      let stream = session.streamResponse(
        to: "What is the weather in New York City, USA?",
        options: options,
      )

      for try await _ in stream {}
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
