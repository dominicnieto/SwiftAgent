// By Dennis Muller

import SwiftAgent

enum AnthropicTextScenario {
  static let scenario = AgentRecorderScenario(
    id: "anthropic/text",
    provider: .anthropic,
    unitTestFile: "Tests/SwiftAgentTests/Providers/AnthropicProviderReplayTests.swift",
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
        instructions: "Reply with exactly: Hello from Claude",
      )

      _ = try await session.respond(to: "Hello?")
    },
  )
}
