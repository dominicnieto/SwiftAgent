// By Dennis Müller

import AnthropicSession
import SwiftAgent

enum AnthropicStreamingTextScenario {
  /// Matches: `Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingTextTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "anthropic/streaming-text",
    provider: .anthropic,
    unitTestFile: "Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingTextTests.swift",
    expectedRecordedResponsesCount: 1,
    run: { recorder, secrets in
      let configuration = try AnthropicConfiguration.recording(
        apiKey: secrets.anthropicAPIKey(),
        recorder: recorder,
      )

      let session = AnthropicSession(
        schema: RecordingSchema(),
        instructions: "Reply with exactly: Hello",
        configuration: configuration,
      )

      let stream = try session.streamResponse(
        to: "prompt",
        using: AnthropicRecordingModel.model,
      )

      for try await _ in stream {}
    },
  )
}

@SessionSchema
private struct RecordingSchema {}
