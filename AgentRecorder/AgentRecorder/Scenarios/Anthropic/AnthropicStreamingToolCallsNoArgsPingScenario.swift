// By Dennis Müller

import AnthropicSession
import SwiftAgent

enum AnthropicStreamingToolCallsNoArgsPingScenario {
  /// Matches: `Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingToolCallsNoArgsTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "anthropic/streaming-tool-calls/no-args-ping",
    provider: .anthropic,
    unitTestFile: "Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingToolCallsNoArgsTests.swift",
    expectedRecordedResponsesCount: 2,
    run: { recorder, secrets in
      let configuration = try AnthropicConfiguration.recording(
        apiKey: secrets.anthropicAPIKey(),
        recorder: recorder,
      )

      let session = AnthropicSession(
        schema: RecordingSchema(),
        instructions: """
        Do not write any text before the tool call.
        Call `ping` exactly once with empty JSON {}.
        After tool output, reply with exactly: pong
        """,
        configuration: configuration,
      )

      let stream = try session.streamResponse(
        to: "Ping",
        using: AnthropicRecordingModel.model,
      )

      for try await _ in stream {}
    },
  )
}

@SessionSchema
private struct RecordingSchema {
  @Tool var ping = PingTool()
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
