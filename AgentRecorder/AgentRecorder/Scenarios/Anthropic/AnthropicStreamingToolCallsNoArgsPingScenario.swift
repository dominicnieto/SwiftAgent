// By Dennis Muller

import SwiftAgent

enum AnthropicStreamingToolCallsNoArgsPingScenario {
  static let scenario = AgentRecorderScenario(
    id: "anthropic/streaming-tool-calls/no-args-ping",
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
        tools: [PingTool()],
        instructions: """
        Do not write any text before the tool call.
        Call `ping` exactly once with empty JSON {}.
        After tool output, reply with exactly: pong
        """,
      )

      let stream = session.streamResponse(to: "Ping")

      for try await _ in stream {}
    },
  )
}

private struct PingTool: SwiftAgent.Tool {
  var name: String = "ping"
  var description: String = "Returns pong with no arguments."

  @Generable
  struct Arguments {}

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "pong"
  }
}
