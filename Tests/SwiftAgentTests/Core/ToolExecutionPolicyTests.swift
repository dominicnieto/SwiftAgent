import Foundation
import Testing

@testable import SwiftAgent

struct ToolExecutionPolicyTests {
  @Test func retriesRegisteredToolNonCancellationFailures() async throws {
    let attempts = ToolAttemptCounter()
    let tool = FlakyWeatherTool(attempts: attempts)
    let session = AgentSession(
      model: NoopLanguageModel(),
      tools: [tool],
      configuration: .init(toolExecutionPolicy: .init(retryPolicy: .retryNonCancellationErrors(maxAttempts: 2)))
    )
    let call = Transcript.ToolCall(
      id: "call_weather",
      toolName: "get_weather",
      arguments: try GeneratedContent(json: #"{"city":"Spokane"}"#),
    )

    let outcome = try await session.executeToolCalls([call])

    guard case let .outputs(results) = outcome else {
      Issue.record("Expected tool outputs")
      return
    }
    #expect(results.count == 1)
    #expect(await attempts.value == 2)
  }

  @Test func recordsMissingToolOutputWhenConfigured() async throws {
    let session = AgentSession(
      model: NoopLanguageModel(),
      configuration: .init(toolExecutionPolicy: .init(missingToolBehavior: .recordErrorOutput))
    )
    let call = try toolCall(id: "missing", toolName: "missing_tool")

    let outcome = try await session.executeToolCalls([call])

    guard case let .outputs(results) = outcome else {
      Issue.record("Expected recorded missing-tool output")
      return
    }
    #expect(results.first?.output.toolName == "missing_tool")
    #expect(session.transcript.entries.contains { entry in
      if case .toolOutput = entry { return true }
      return false
    })
  }

  @Test func throwsMissingToolErrorWhenConfigured() async throws {
    let session = AgentSession(
      model: NoopLanguageModel(),
      configuration: .init(toolExecutionPolicy: .init(missingToolBehavior: .throwError))
    )
    let call = try toolCall(id: "missing", toolName: "missing_tool")

    await #expect(throws: AgentSession.ToolCallError.self) {
      _ = try await session.executeToolCalls([call])
    }
  }

  @Test func recordsRegisteredToolFailureOutputWhenConfigured() async throws {
    let session = AgentSession(
      model: NoopLanguageModel(),
      tools: [AlwaysFailingTool()],
      configuration: .init(toolExecutionPolicy: .init(failureBehavior: .recordErrorOutput))
    )
    let call = try toolCall(id: "fail", toolName: "always_fail")

    let outcome = try await session.executeToolCalls([call])

    guard case let .outputs(results) = outcome else {
      Issue.record("Expected recorded failure output")
      return
    }
    #expect(results.first?.output.toolName == "always_fail")
  }

  @Test func recordsRegisteredToolFailureOutputWhenStopOnToolErrorIsDisabled() async throws {
    let session = AgentSession(
      model: NoopLanguageModel(),
      tools: [AlwaysFailingTool()],
      configuration: .init(stopOnToolError: false)
    )
    let call = try toolCall(id: "fail", toolName: "always_fail")

    let outcome = try await session.executeToolCalls([call])

    guard case let .outputs(results) = outcome else {
      Issue.record("Expected recorded failure output")
      return
    }
    #expect(results.first?.output.toolName == "always_fail")
  }

  @Test func throwsRegisteredToolFailureByDefault() async throws {
    let session = AgentSession(model: NoopLanguageModel(), tools: [AlwaysFailingTool()])
    let call = try toolCall(id: "fail", toolName: "always_fail")

    await #expect(throws: AgentSession.ToolCallError.self) {
      _ = try await session.executeToolCalls([call])
    }
  }

  @Test func recordsMissingToolOutputWhenStopOnToolErrorIsDisabled() async throws {
    let session = AgentSession(
      model: NoopLanguageModel(),
      configuration: .init(
        toolExecutionPolicy: .init(missingToolBehavior: .throwError),
        stopOnToolError: false,
      )
    )
    let call = try toolCall(id: "missing", toolName: "missing_tool")

    let outcome = try await session.executeToolCalls([call])

    guard case let .outputs(results) = outcome else {
      Issue.record("Expected recorded missing-tool output")
      return
    }
    #expect(results.first?.output.toolName == "missing_tool")
  }

  @Test func delegateCanStopToolExecution() async throws {
    let delegate = StopToolDelegate()
    let session = AgentSession(model: NoopLanguageModel(), tools: [EchoTool()])
    session.toolExecutionDelegate = delegate
    let call = try toolCall(id: "echo", toolName: "echo")

    let outcome = try await session.executeToolCalls([call])

    guard case let .stop(calls) = outcome else {
      Issue.record("Expected delegate stop outcome")
      return
    }
    #expect(calls.map(\.id) == ["echo"])
  }

  @Test func delegateCanProvideToolOutput() async throws {
    let delegate = ProvideOutputToolDelegate()
    let session = AgentSession(model: NoopLanguageModel(), tools: [AlwaysFailingTool()])
    session.toolExecutionDelegate = delegate
    let call = try toolCall(id: "provided", toolName: "always_fail")

    let outcome = try await session.executeToolCalls([call])

    guard case let .outputs(results) = outcome else {
      Issue.record("Expected provided output")
      return
    }
    guard case let .text(text)? = results.first?.output.segment else {
      Issue.record("Expected text output")
      return
    }
    #expect(text.content == "provided")
  }

  @Test func cancellationErrorsAreNotRetried() async throws {
    let attempts = ToolAttemptCounter()
    let session = AgentSession(
      model: NoopLanguageModel(),
      tools: [CancellingTool(attempts: attempts)],
      configuration: .init(toolExecutionPolicy: .init(retryPolicy: .retryNonCancellationErrors(maxAttempts: 3)))
    )
    let call = try toolCall(id: "cancel", toolName: "cancel")

    await #expect(throws: CancellationError.self) {
      _ = try await session.executeToolCalls([call])
    }
    #expect(await attempts.value == 1)
  }

  @Test func parallelPolicyAllowsConcurrentToolExecution() async throws {
    let tracker = ToolConcurrencyTracker()
    let session = AgentSession(
      model: NoopLanguageModel(),
      tools: [TrackedTool(tracker: tracker)],
      configuration: .init(toolExecutionPolicy: .init(allowsParallelExecution: true))
    )
    let first = try toolCall(id: "first", toolName: "tracked")
    let second = try toolCall(id: "second", toolName: "tracked")

    _ = try await session.executeToolCalls([first, second])

    #expect(await tracker.maximumConcurrentExecutions > 1)
  }

  @Test func serialPolicyRunsToolCallsOneAtATime() async throws {
    let tracker = ToolConcurrencyTracker()
    let session = AgentSession(
      model: NoopLanguageModel(),
      tools: [TrackedTool(tracker: tracker)],
      configuration: .init(toolExecutionPolicy: .init(allowsParallelExecution: false))
    )
    let first = try toolCall(id: "first", toolName: "tracked")
    let second = try toolCall(id: "second", toolName: "tracked")

    _ = try await session.executeToolCalls([first, second])

    #expect(await tracker.maximumConcurrentExecutions == 1)
  }
}

private func toolCall(id: String, toolName: String) throws -> Transcript.ToolCall {
  try Transcript.ToolCall(
    id: id,
    toolName: toolName,
    arguments: GeneratedContent(json: #"{"city":"Spokane"}"#),
  )
}

private actor ToolAttemptCounter {
  private var count = 0

  var value: Int {
    count
  }

  func increment() -> Int {
    count += 1
    return count
  }
}

private struct FlakyWeatherTool: Tool {
  var attempts: ToolAttemptCounter
  var name: String { "get_weather" }
  var description: String { "Returns weather for a city." }

  @Generable
  struct Arguments {
    var city: String
  }

  func call(arguments: Arguments) async throws -> String {
    let attempt = await attempts.increment()
    if attempt == 1 {
      throw FlakyWeatherError()
    }
    return "Sunny in \(arguments.city)"
  }
}

private struct FlakyWeatherError: Error, LocalizedError {
  var errorDescription: String? { "Temporary weather failure" }
}

private struct AlwaysFailingTool: Tool {
  var name: String { "always_fail" }
  var description: String { "Always fails." }

  @Generable
  struct Arguments {
    var city: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    throw FlakyWeatherError()
  }
}

private struct EchoTool: Tool {
  var name: String { "echo" }
  var description: String { "Echoes the city." }

  @Generable
  struct Arguments {
    var city: String
  }

  func call(arguments: Arguments) async throws -> String {
    arguments.city
  }
}

private struct CancellingTool: Tool {
  var attempts: ToolAttemptCounter
  var name: String { "cancel" }
  var description: String { "Cancels." }

  @Generable
  struct Arguments {
    var city: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    _ = await attempts.increment()
    throw CancellationError()
  }
}

private actor ToolConcurrencyTracker {
  private var activeExecutions = 0
  private var maximumActiveExecutions = 0

  var maximumConcurrentExecutions: Int {
    maximumActiveExecutions
  }

  func started() {
    activeExecutions += 1
    maximumActiveExecutions = max(maximumActiveExecutions, activeExecutions)
  }

  func finished() {
    activeExecutions -= 1
  }
}

private struct TrackedTool: Tool {
  var tracker: ToolConcurrencyTracker
  var name: String { "tracked" }
  var description: String { "Tracks concurrency." }

  @Generable
  struct Arguments {
    var city: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    await tracker.started()
    try await Task.sleep(for: .milliseconds(25))
    await tracker.finished()
    return "done"
  }
}

private struct StopToolDelegate: ToolExecutionDelegate {
  func toolCallDecision(
    for toolCall: Transcript.ToolCall,
    in session: any ToolExecutionContext,
  ) async -> ToolExecutionDecision {
    _ = toolCall
    _ = session
    return .stop
  }
}

private struct ProvideOutputToolDelegate: ToolExecutionDelegate {
  func toolCallDecision(
    for toolCall: Transcript.ToolCall,
    in session: any ToolExecutionContext,
  ) async -> ToolExecutionDecision {
    _ = toolCall
    _ = session
    return .provideOutput([.text(.init(content: "provided"))])
  }
}

private struct NoopLanguageModel: LanguageModel {
  typealias UnavailableReason = Never


}
