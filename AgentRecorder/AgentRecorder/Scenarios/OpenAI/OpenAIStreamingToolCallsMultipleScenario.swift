// By Dennis Müller

import OpenAISession
import SwiftAgent

enum OpenAIStreamingToolCallsMultipleScenario {
  /// Matches: `Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingMultipleToolCallsTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "openai/streaming-tool-calls/multiple",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingMultipleToolCallsTests.swift",
    expectedRecordedResponsesCount: 2,
    run: { recorder, secrets in
      let configuration = try OpenAIConfiguration.recording(
        apiKey: secrets.openAIAPIKey(),
        recorder: recorder,
      )

      let session = OpenAISession(
        schema: RecordingSchema(),
        instructions: """
        Do not answer with any text before tool calls.
        Call `get_weather` with { "location": "Tokyo" } and `get_time` with { "location": "Tokyo" } in parallel.
        After tool outputs, reply with exactly: Done.
        """,
        configuration: configuration,
      )

      let stream = try session.streamResponse(
        to: "Need weather and time.",
        using: .gpt4o,
        options: .init(
          allowParallelToolCalls: true,
          minimumStreamingSnapshotInterval: .zero,
        ),
      )

      for try await _ in stream {}
    },
  )
}

@SessionSchema
private struct RecordingSchema {
  @Tool var weather = WeatherTool()
  @Tool var time = TimeTool()
}

private struct WeatherTool: SwiftAgent.Tool {
  var name: String = "get_weather"
  var description: String = "Get current weather for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}

private struct TimeTool: SwiftAgent.Tool {
  var name: String = "get_time"
  var description: String = "Get the current local time for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "12:34"
  }
}
