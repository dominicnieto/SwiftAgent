// By Dennis Muller

import SwiftAgent

enum AnthropicStreamingThinkingScenario {
  static let scenario = AgentRecorderScenario(
    id: "anthropic/streaming-thinking",
    provider: .anthropic,
    unitTestFile: "Tests/SwiftAgentTests/Providers/AnthropicProviderReplayTests.swift",
    expectedRecordedResponsesCount: 2,
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

      var options = GenerationOptions(maximumResponseTokens: 2_048)
      options[custom: AnthropicLanguageModel.self] = .init(
        thinking: .init(budgetTokens: 1_024),
      )

      let stream = session.streamResponse(
        to: "First prompt",
        options: options,
      )

      for try await _ in stream {}

      _ = try await session.respond(
        to: "Second prompt",
        options: options,
      )
    },
  )
}
