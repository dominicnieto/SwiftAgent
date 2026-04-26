// By Dennis Muller

import SwiftAgent

enum AnthropicStreamingTextScenario {
  static let scenario = AgentRecorderScenario(
    id: "anthropic/streaming-text",
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
        instructions: "Reply with exactly: Hello",
      )

      let stream = session.streamResponse(to: "prompt")

      for try await _ in stream {}
    },
  )
}
