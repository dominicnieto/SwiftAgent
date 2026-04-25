// By Dennis Müller

import OpenAI
import OpenAISession
import SwiftAgent

enum OpenAIStructuredOutputScenario {
  /// Matches: `Tests/SwiftAgentTests/OpenAISession/OpenAIStructuredOutputTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "openai/structured-output",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/OpenAISession/OpenAIStructuredOutputTests.swift",
    expectedRecordedResponsesCount: 1,
    run: { recorder, secrets in
      let configuration = try OpenAIConfiguration.recording(
        apiKey: secrets.openAIAPIKey(),
        recorder: recorder,
      )

      let session = OpenAISession(
        schema: RecordingSchema(),
        instructions: "Return temperatureCelsius=22 and condition=Partly Cloudy.",
        configuration: configuration,
      )

      _ = try await session.respond(
        to: "Provide the latest weather update.",
        generating: WeatherForecast.self,
        using: OpenAIRecordingModel.model,
        options: .init(
          include: [.reasoning_encryptedContent],
          reasoning: .init(
            effort: .low,
            summary: .detailed,
          ),
        ),
      )
    },
  )
}

@SessionSchema
private struct RecordingSchema {
  @StructuredOutput(WeatherForecast.self) var weatherForecast
}

private struct WeatherForecast: StructuredOutput {
  static let name: String = "weather_forecast"

  @Generable
  struct Schema {
    var temperatureCelsius: Double
    var condition: String
  }
}
