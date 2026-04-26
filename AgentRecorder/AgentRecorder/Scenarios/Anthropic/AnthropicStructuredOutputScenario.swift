// By Dennis Muller

import SwiftAgent

enum AnthropicStructuredOutputScenario {
  static let scenario = AgentRecorderScenario(
    id: "anthropic/structured-output",
    provider: .anthropic,
    unitTestFile: "Tests/SwiftAgentTests/Core/DirectProviderReplayTests.swift",
    expectedRecordedResponsesCount: 1,
    run: { recorder, secrets in
      let apiKey = try secrets.anthropicAPIKey()
      let model = AnthropicLanguageModel(
        apiKey: apiKey,
        model: AnthropicRecordingModel.model,
        httpClient: AnthropicRecordingHTTPClient.make(apiKey: apiKey, recorder: recorder),
      )
      let session = LanguageModelSession(
        model: model,
        instructions: "Return temperature=21 and condition=Sunny.",
      )

      _ = try await session.respond(
        to: Prompt("Weather update"),
        generating: WeatherReport.self,
      )
    },
  )
}

@Generable
private struct WeatherReport {
  var temperature: Int
  var condition: String
}
