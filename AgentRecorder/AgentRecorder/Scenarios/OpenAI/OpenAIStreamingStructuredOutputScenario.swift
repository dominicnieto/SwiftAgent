// By Dennis Müller

import OpenAI
import OpenAISession
import SwiftAgent

enum OpenAIStreamingStructuredOutputScenario {
  /// Matches: `Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingStructuredOutputTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "openai/streaming-structured-output",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingStructuredOutputTests.swift",
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

      let stream = try session.streamResponse(
        to: "Provide the latest weather update.",
        generating: \.weatherForecast,
        using: OpenAIRecordingModel.model,
        options: .init(
          include: [.reasoning_encryptedContent],
          reasoning: .init(
            effort: .low,
            summary: .detailed,
          ),
          minimumStreamingSnapshotInterval: .zero,
        ),
      )

      for try await _ in stream {}
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
