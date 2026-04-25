// By Dennis Müller

import OpenAI
import OpenAISession
import SwiftAgent

enum OpenAIStreamingToolCallsWeatherScenario {
  /// Matches: `Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingToolCallsTests.swift`
  static let scenario = AgentRecorderScenario(
    id: "openai/streaming-tool-calls/weather",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingToolCallsTests.swift",
    expectedRecordedResponsesCount: 2,
    run: { recorder, secrets in
      let configuration = try OpenAIConfiguration.recording(
        apiKey: secrets.openAIAPIKey(),
        recorder: recorder,
      )

      let session = OpenAISession(
        schema: RecordingSchema(),
        instructions: """
        Always call `get_weather` exactly once before answering.
        After tool output, reply with exactly: Current weather in New York City, USA: Sunny.
        """,
        configuration: configuration,
      )

      let prompt = "What is the weather in New York City, USA?"
      let stream = try session.streamResponse(
        to: prompt,
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
private struct RecordingSchema {
  @Tool var weather = WeatherTool()
}

private struct WeatherTool: SwiftAgent.Tool {
  var name: String = "get_weather"
  var description: String = "Get current temperature for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}
