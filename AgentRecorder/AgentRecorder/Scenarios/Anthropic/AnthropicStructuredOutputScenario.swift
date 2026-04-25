// By Dennis Müller

import AnthropicSession
import SwiftAgent

enum AnthropicStructuredOutputScenario {
  /// Matches: `Tests/SwiftAgentTests/AnthropicSession/AnthropicStructuredOutputTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "anthropic/structured-output",
    provider: .anthropic,
    unitTestFile: "Tests/SwiftAgentTests/AnthropicSession/AnthropicStructuredOutputTests.swift",
    expectedRecordedResponsesCount: 1,
    run: { recorder, secrets in
      let configuration = try AnthropicConfiguration.recording(
        apiKey: secrets.anthropicAPIKey(),
        recorder: recorder,
      )

      let session = AnthropicSession(
        schema: RecordingSchema(),
        instructions: "Return temperature=21 and condition=Sunny.",
        configuration: configuration,
      )

      _ = try await session.respond(
        to: "Weather update",
        generating: WeatherReport.self,
        using: AnthropicRecordingModel.model,
      )
    },
  )
}

@SessionSchema
private struct RecordingSchema {
  @StructuredOutput(WeatherReport.self) var weatherReport
}

private struct WeatherReport: StructuredOutput {
  static let name: String = "weather_report"

  @Generable
  struct Schema {
    var temperature: Int
    var condition: String
  }
}
