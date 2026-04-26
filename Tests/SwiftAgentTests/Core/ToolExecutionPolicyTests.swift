import Foundation
import Testing

@testable import SwiftAgent

struct ToolExecutionPolicyTests {
  @Test func retriesRegisteredToolNonCancellationFailures() async throws {
    let attempts = ToolAttemptCounter()
    let tool = FlakyWeatherTool(attempts: attempts)
    let session = LanguageModelSession(
      model: NoopLanguageModel(),
      tools: [tool],
      toolExecutionPolicy: .init(retryPolicy: .retryNonCancellationErrors(maxAttempts: 2)),
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

private struct NoopLanguageModel: LanguageModel {
  typealias UnavailableReason = Never

  func respond<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) async throws -> LanguageModelSession.Response<Content> where Content: Generable & Sendable {
    _ = session
    _ = prompt
    _ = type
    _ = includeSchemaInPrompt
    _ = options
    throw LanguageModelSession.GenerationError.decodingFailure(.init(debugDescription: "Noop model"))
  }

  func streamResponse<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions,
  ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable & Sendable, Content.PartiallyGenerated: Sendable {
    _ = session
    _ = prompt
    _ = type
    _ = includeSchemaInPrompt
    _ = options
    return LanguageModelSession.ResponseStream(stream: AsyncThrowingStream { $0.finish() })
  }
}
