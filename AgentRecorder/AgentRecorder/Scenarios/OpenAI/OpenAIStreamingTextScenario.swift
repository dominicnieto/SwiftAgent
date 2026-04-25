// By Dennis Müller

import OpenAI
import OpenAISession
import SwiftAgent

enum OpenAIStreamingTextScenario {
  /// Matches: `Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingTextTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "openai/streaming-text",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingTextTests.swift",
    expectedRecordedResponsesCount: 1,
    run: { recorder, secrets in
      let configuration = try OpenAIConfiguration.recording(
        apiKey: secrets.openAIAPIKey(),
        recorder: recorder,
      )

      let session = OpenAISession(
        schema: RecordingSchema(),
        instructions: "Reply with exactly: Hello, World!",
        configuration: configuration,
      )

      let stream = try session.streamResponse(
        to: "prompt",
        using: OpenAIRecordingModel.model,
        options: .init(
          include: [.reasoning_encryptedContent],
          reasoning: .init(
            effort: .low,
            summary: .detailed,
          ),
        ),
      )

      for try await _ in stream {}
    },
  )
}

@SessionSchema
private struct RecordingSchema {}
