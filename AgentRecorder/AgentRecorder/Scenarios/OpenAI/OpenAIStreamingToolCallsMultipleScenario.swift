// By Dennis Muller

import SwiftAgent

enum OpenAIStreamingToolCallsMultipleScenario {
  static let scenario = AgentRecorderScenario(
    id: "openai/streaming-tool-calls/multiple",
    provider: .openAI,
    unitTestFile: "Tests/SwiftAgentTests/Providers/OpenAIProviderReplayTests.swift",
    expectedRecordedResponsesCount: 2,
    run: { recorder, secrets in
      let apiKey = try secrets.openAIAPIKey()
      let model = OpenAILanguageModel(
        apiKey: apiKey,
        model: "gpt-4o",
        apiVariant: .responses,
        httpClient: OpenAIRecordingHTTPClient.make(apiKey: apiKey, recorder: recorder),
      )
      let session = LanguageModelSession(
        model: model,
        tools: [WeatherTool(), TimeTool()],
        instructions: """
        Do not answer with any text before tool calls.
        Call `get_weather` with { "location": "Tokyo" } and `get_time` with { "location": "Tokyo" } in parallel.
        After tool outputs, reply with exactly: Done.
        """,
        toolExecutionPolicy: .init(allowsParallelExecution: true),
      )

      let stream = session.streamResponse(
        to: "Need weather and time.",
        options: GenerationOptions(minimumStreamingSnapshotInterval: .zero),
      )

      for try await _ in stream {}
    },
  )
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
