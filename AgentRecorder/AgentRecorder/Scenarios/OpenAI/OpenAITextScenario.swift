// By Dennis Müller

import OpenAISession
import SwiftAgent

enum OpenAITextScenario {
  /// Matches: `Tests/SwiftAgentTests/OpenAISession/OpenAITextTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "openai/text",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/OpenAISession/OpenAITextTests.swift",
    expectedRecordedResponsesCount: 1,
    run: { recorder, secrets in
      let configuration = try OpenAIConfiguration.recording(
        apiKey: secrets.openAIAPIKey(),
        recorder: recorder,
      )

      let session = OpenAISession(
        schema: RecordingSchema(),
        instructions: "Reply with exactly: Hello from OpenAI",
        configuration: configuration,
      )

      _ = try await session.respond(
        to: "Hello?",
        using: .gpt4o,
      )
    },
  )
}

@SessionSchema
private struct RecordingSchema {}
