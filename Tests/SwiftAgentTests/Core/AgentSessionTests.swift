import Foundation
import Testing

@testable import SwiftAgent

struct AgentSessionTests {
  @SessionSchema
  struct GroundedSchema {
    @Grounding(Date.self) var currentDate
    @StructuredOutput(AgentWeatherReport.self) var weatherReport
  }

  @SessionSchema
  struct RejectionSchema {
    @Tool var rejectingLookup = RejectingLookupTool()
  }

  @Test func agentRunStoresTypedGroundingsInTranscript() async throws {
    let provider = AgentSessionMockProvider(responses: [
      ModelResponse(content: GeneratedContent("Grounded agent response"), finishReason: .completed),
    ])
    let schema = GroundedSchema()
    let session = AgentSession(model: provider)
    let date = Date(timeIntervalSince1970: 1_234)

    let result = try await session.run(
      to: "What day is it?",
      schema: schema,
      groundingWith: [.currentDate(date)],
    ) { input, sources in
      PromptTag("context") {
        for source in sources {
          if case let .currentDate(date) = source {
            "Current date: \(date)"
          }
        }
      }

      PromptTag("input") {
        input
      }
    }

    #expect(result.content == "Grounded agent response")
    let resolved = try schema.resolve(session.transcript)
    let prompt = try #require(resolved.compactMap { entry -> Transcript.Resolved<GroundedSchema>.Prompt? in
      guard case let .prompt(prompt) = entry else { return nil }
      return prompt
    }.first)
    #expect(prompt.input == "What day is it?")
    #expect(prompt.sources == [.currentDate(date)])
    #expect(prompt.prompt.contains("Current date:"))
  }

  @Test func agentRunSupportsSessionSchemaStructuredOutputKeyPath() async throws {
    let provider = AgentSessionMockProvider(responses: [
      ModelResponse(
        content: GeneratedContent(properties: ["summary": "Sunny", "temperatureCelsius": 24]),
        finishReason: .completed,
      ),
    ])
    let schema = GroundedSchema()
    let session = AgentSession(model: provider)

    let result = try await session.run(
      to: "Weather in Lisbon?",
      generating: \.weatherReport,
      schema: schema,
      groundingWith: [],
    ) { input, _ in
      Prompt(input)
    }

    #expect(result.content.summary == "Sunny")
    #expect(result.content.temperatureCelsius == 24)
    #expect(result.steps.count == 1)
    let request = try #require(provider.recordedRequests.first)
    #expect(request.structuredOutput != nil)
  }

  @Test func agentStreamEmitsTypedPartialContentAndTypedCompletion() async throws {
    let partialContent = GeneratedContent(properties: ["summary": "Sun"])
    let finalContent = GeneratedContent(properties: ["summary": "Sunny", "temperatureCelsius": 24])
    let provider = AgentSessionMockProvider(events: [
      .structuredDelta(id: "forecast-1", delta: partialContent),
      .structuredDelta(id: "forecast-1", delta: finalContent),
      .completed(.init(finishReason: .completed)),
    ])
    let session = AgentSession(model: provider)

    var sawPartialContent = false
    var completed: AgentResult<ProviderReplayForecast>?
    for try await event in session.stream(
      to: "Weather in Lisbon?",
      generating: ProviderReplayForecast.self,
      options: GenerationOptions(minimumStreamingSnapshotInterval: .zero),
    ) {
      if case .partialContent = event {
        sawPartialContent = true
      }
      if case let .completed(result) = event {
        completed = result
      }
    }

    #expect(sawPartialContent)
    let result = try #require(completed)
    #expect(result.content.summary == "Sunny")
    #expect(result.content.temperatureCelsius == 24)
    #expect(result.iterationCount == 1)
  }

  @Test func agentResultIncludesPerStepToolHistory() async throws {
    let toolCall = Transcript.ToolCall(
      id: "tool-1",
      callId: "call-1",
      toolName: "lookup",
      arguments: GeneratedContent(properties: ["query": "forecast"]),
      status: .completed,
    )
    let provider = AgentSessionMockProvider(responses: [
      ModelResponse(
        toolCalls: [ModelToolCall(call: toolCall, kind: .local)],
        finishReason: .toolCalls,
      ),
      ModelResponse(
        content: GeneratedContent("Tool result incorporated"),
        finishReason: .completed,
      ),
    ])
    let session = AgentSession(
      model: provider,
      tools: [AgentLookupTool()],
      configuration: .init(toolExecutionPolicy: .init(allowsParallelExecution: false)),
    )

    let result = try await session.run(to: "Look up the forecast")

    #expect(result.content == "Tool result incorporated")
    #expect(result.iterationCount == 2)
    #expect(result.steps.count == 2)
    #expect(result.toolCalls.map(\.id) == ["tool-1"])
    #expect(result.toolOutputs.map(\.callId) == ["call-1"])
    #expect(result.steps[0].toolCalls.map(\.id) == ["tool-1"])
    #expect(result.steps[0].toolOutputs.map(\.callId) == ["call-1"])
  }

  @Test func agentRunResolvesToolRunRejectionThroughSessionSchema() async throws {
    let schema = RejectionSchema()
    let toolCall = Transcript.ToolCall(
      id: "rejecting-tool-1",
      callId: "rejecting-call-1",
      toolName: "rejecting_lookup",
      arguments: GeneratedContent(properties: ["location": "Tokyo"]),
      status: .completed,
    )
    let provider = AgentSessionMockProvider(responses: [
      ModelResponse(
        toolCalls: [ModelToolCall(call: toolCall, kind: .local)],
        finishReason: .toolCalls,
      ),
      ModelResponse(
        content: GeneratedContent("Recovered after rejection"),
        finishReason: .completed,
      ),
    ])
    let session = AgentSession(
      model: provider,
      schema: schema,
      configuration: .init(toolExecutionPolicy: .init(allowsParallelExecution: false)),
    )

    let result = try await session.run(to: "Look up Tokyo")

    #expect(result.content == "Recovered after rejection")
    #expect(result.iterationCount == 2)
    #expect(result.steps[0].toolOutputs.map(\.callId) == ["rejecting-call-1"])
    #expect(provider.recordedRequests.first?.tools.map(\.name) == ["rejecting_lookup"])

    let resolved = try schema.resolve(session.transcript)
    let resolvedRun = try #require(resolved.compactMap { entry -> ToolRun<RejectingLookupTool>? in
      guard case let .toolRun(decodedRun) = entry,
            case let .rejectingLookup(run) = decodedRun else {
        return nil
      }
      return run
    }.first)

    #expect(resolvedRun.finalArguments?.location == "Tokyo")
    #expect(resolvedRun.output == nil)
    #expect(resolvedRun.hasRejection)
    #expect(resolvedRun.rejection?.reason == "Location unavailable")
    #expect(resolvedRun.rejection?.details["details"] == #"{"location":"Tokyo"}"#)
  }

  @Test func languageModelSessionSchemaInitializerRegistersSchemaTools() async throws {
    let schema = RejectionSchema()
    let provider = AgentSessionMockProvider(responses: [
      ModelResponse(content: GeneratedContent("Direct response"), finishReason: .completed),
    ])
    let session = LanguageModelSession(
      model: provider,
      schema: schema,
      instructions: "Expose schema tools for manual tool-call inspection.",
    )

    _ = try await session.respond(to: "Which tools are available?")

    #expect(session.tools.map(\.name) == ["rejecting_lookup"])
    #expect(provider.recordedRequests.first?.tools.map(\.name) == ["rejecting_lookup"])
  }

  @Test func streamingAgentDoesNotExecuteProviderDefinedToolCalls() async throws {
    let serverToolCall = Transcript.ToolCall(
      id: "server-tool-1",
      callId: "server-call-1",
      toolName: "server_search",
      arguments: GeneratedContent(properties: ["query": "forecast"]),
      status: .completed,
    )
    let provider = AgentSessionMockProvider(events: [
      .toolCallsCompleted([ModelToolCall(call: serverToolCall, kind: .providerDefined)], continuation: nil),
      .completed(.init(finishReason: .completed)),
    ])
    let session = AgentSession(model: provider, tools: [AgentLookupTool()])

    var sawExecutionStart = false
    var sawToolOutput = false
    var completed: AgentResult<String>?
    for try await event in session.stream(to: "Search from the provider side") {
      if case .toolExecutionStarted = event {
        sawExecutionStart = true
      }
      if case .toolOutput = event {
        sawToolOutput = true
      }
      if case let .completed(result) = event {
        completed = result
      }
    }

    #expect(sawExecutionStart == false)
    #expect(sawToolOutput == false)
    #expect(completed?.toolCalls.isEmpty == true)
    #expect(completed?.toolOutputs.isEmpty == true)
    #expect(session.transcript.entries.contains { entry in
      guard case let .toolCalls(toolCalls) = entry else { return false }
      return toolCalls.calls == [serverToolCall]
    })
    #expect(session.transcript.entries.contains { entry in
      if case .toolOutput = entry { return true }
      return false
    } == false)
  }
}

struct AgentWeatherReport: StructuredOutput {
  static let name = "agent_weather_report"

  @Generable
  struct Schema {
    var summary: String
    var temperatureCelsius: Int
  }
}

private final class AgentSessionMockProvider: LanguageModel, @unchecked Sendable {
  typealias UnavailableReason = Never

  private let lock = NSLock()
  private var responses: [ModelResponse]
  private var requests: [ModelRequest] = []
  private let events: [ModelStreamEvent]

  var recordedRequests: [ModelRequest] {
    lock.withLock { requests }
  }

  init(responses: [ModelResponse] = [], events: [ModelStreamEvent] = []) {
    self.responses = responses
    self.events = events
  }

  func respond(to request: ModelRequest) async throws -> ModelResponse {
    try lock.withLock {
      requests.append(request)
      guard responses.isEmpty == false else {
        throw LanguageModelContractError.neutralTurnNotImplemented(modelType: String(reflecting: Self.self))
      }
      return responses.removeFirst()
    }
  }

  func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
    lock.withLock {
      requests.append(request)
    }
    let events = events
    return AsyncThrowingStream { continuation in
      for event in events {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private struct AgentLookupTool: Tool {
  let name = "lookup"
  let description = "Looks up a value."

  @Generable
  struct Arguments {
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    "Lookup result for \(arguments.query)"
  }
}

struct RejectingLookupTool: Tool {
  let name = "rejecting_lookup"
  let description = "Looks up a value and can return a recoverable rejection."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    throw ToolRunRejection(
      reason: "Location unavailable",
      details: ["location": arguments.location],
    )
  }
}
