// By Dennis Muller

import SwiftAgent

enum OpenAIStreamingStructuredOutputScenario {
  static let scenario = AgentRecorderScenario(
    id: "openai/streaming-structured-output",
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

      var options = GenerationOptions(minimumStreamingSnapshotInterval: .zero)
      options[custom: OpenAILanguageModel.self] = .init(
        reasoning: .init(effort: .low, summary: "detailed"),
      )

      let stream = session.streamResponse(
        to: Prompt("Provide the latest weather update."),
        generating: WeatherForecast.self,
        options: options,
      )

      for try await _ in stream {}
    },
  )
}

@Generable
private struct WeatherForecast {
  var temperatureCelsius: Double
  var condition: String
}
