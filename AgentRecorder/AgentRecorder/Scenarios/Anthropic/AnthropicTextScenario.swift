// By Dennis Müller

import AnthropicSession
import SwiftAgent

enum AnthropicTextScenario {
  /// Matches: `Tests/SwiftAgentTests/AnthropicSession/AnthropicTextTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "anthropic/text",
    provider: .anthropic,
    unitTestFile: "Tests/SwiftAgentTests/AnthropicSession/AnthropicTextTests.swift",
    expectedRecordedResponsesCount: 1,
    run: { recorder, secrets in
      let configuration = try AnthropicConfiguration.recording(
        apiKey: secrets.anthropicAPIKey(),
        recorder: recorder,
      )

      let session = AnthropicSession(
        schema: RecordingSchema(),
        instructions: "Reply with exactly: Hello from Claude",
        configuration: configuration,
      )

      _ = try await session.respond(
        to: "Hello?",
        using: AnthropicRecordingModel.model,
      )
    },
  )
}

@SessionSchema
private struct RecordingSchema {}
