// By Dennis Müller

import AnthropicSession
import FoundationModels
import SwiftAgent
import SwiftAnthropic

enum AnthropicStreamingThinkingScenario {
  /// Matches: `Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingThinkingRoundtripTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "anthropic/streaming-thinking",
    provider: .anthropic,
    unitTestFile: "Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingThinkingRoundtripTests.swift",
    expectedRecordedResponsesCount: 2,
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

      let options = AnthropicGenerationOptions(
        maxOutputTokens: 2048,
        thinking: .init(budgetTokens: 1024),
      )

      let stream = try session.streamResponse(
        to: "First prompt",
        using: AnthropicRecordingModel.model,
        options: options,
      )

      for try await _ in stream {}

      _ = try await session.respond(
        to: "Second prompt",
        using: AnthropicRecordingModel.model,
        options: options,
      )
    },
  )
}

@SessionSchema
private struct RecordingSchema {}
