// By Dennis Müller

import SwiftAgent

enum OpenAITextScenario {
  static let scenario = AgentRecorderScenario(
    id: "openai/text",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/Core/DirectProviderReplayTests.swift",
    expectedRecordedResponsesCount: 1,
    run: { recorder, secrets in
      let apiKey = try secrets.openAIAPIKey()
      let model = OpenAILanguageModel(
        apiKey: apiKey,
        model: "gpt-4o",
        apiVariant: .responses,
        httpClient: OpenAIRecordingHTTPClient.make(
          apiKey: apiKey,
          recorder: recorder,
        ),
      )
      let session = LanguageModelSession(
        model: model,
        instructions: "Reply with exactly: Hello from OpenAI",
      )

      _ = try await session.respond(
        to: "Hello?",
      )
    },
  )
}
