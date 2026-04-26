// By Dennis Muller

import SwiftAgent

enum OpenAIStructuredOutputScenario {
  static let scenario = AgentRecorderScenario(
    id: "openai/structured-output",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/Providers/OpenAIProviderReplayTests.swift",
    expectedRecordedResponsesCount: 1,
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
        instructions: "Return temperatureCelsius=22 and condition=Partly Cloudy.",
      )

      var options = GenerationOptions()
      options[custom: OpenAILanguageModel.self] = .init(
        reasoning: .init(effort: .low, summary: "detailed"),
      )

      _ = try await session.respond(
        to: Prompt("Provide the latest weather update."),
        generating: WeatherForecast.self,
        options: options,
      )
    },
  )
}

@Generable
private struct WeatherForecast {
  var temperatureCelsius: Double
  var condition: String
}
