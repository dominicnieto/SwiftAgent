// By Dennis Muller

import SwiftAgent

enum OpenAIStreamingTextScenario {
  static let scenario = AgentRecorderScenario(
    id: "openai/streaming-text",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/Core/DirectProviderReplayTests.swift",
    expectedRecordedResponsesCount: 1,
    run: { recorder, secrets in
      let apiKey = try secrets.openAIAPIKey()
      let model = OpenAILanguageModel(
        apiKey: apiKey,
        model: OpenAIRecordingModel.model,
        apiVariant: .responses,
        httpClient: OpenAIRecordingHTTPClient.make(apiKey: apiKey, recorder: recorder),
      )
      let session = LanguageModelSession(
        model: model,
        instructions: "Reply with exactly: Hello, World!",
      )

      var options = GenerationOptions()
      options[custom: OpenAILanguageModel.self] = .init(
        reasoning: .init(effort: .low, summary: "detailed"),
      )

      let stream = session.streamResponse(to: "prompt", options: options)

      for try await _ in stream {}
    },
  )
}
