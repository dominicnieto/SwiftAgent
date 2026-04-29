import Foundation
import Testing

@testable import SwiftAgent

@Suite("Conversation engine")
struct ConversationEngineTests {
  @SessionSchema
  struct GroundedSchema {
    @Grounding(Date.self) var currentDate
  }

  @Test func engineRunsMockTextTurnAndRecordsTranscriptUsageAndMetadata() async throws {
    let provider = ConversationEngineMockProvider(responses: [
      ModelResponse(
        content: GeneratedContent("Hello from the engine"),
        finishReason: .completed,
        tokenUsage: TokenUsage(inputTokens: 3, outputTokens: 4, totalTokens: 7),
        responseMetadata: ResponseMetadata(id: "response-1", providerName: "MockProvider"),
      ),
    ])
    let engine = ConversationEngine(
      model: provider,
      instructions: Instructions("Reply briefly"),
      tools: [LookupTool()],
    )

    let response = try await engine.respond(
      prompt: Prompt("Say hello"),
      activeToolNames: ["lookup"],
    )

    #expect(response.content == GeneratedContent("Hello from the engine"))
    #expect(await engine.tokenUsage == TokenUsage(inputTokens: 3, outputTokens: 4, totalTokens: 7))
    #expect(await engine.responseMetadata?.id == "response-1")

    let entries = await engine.transcript.entries
    #expect(entries.count == 3)
    guard case let .instructions(instructions) = entries[0] else {
      Issue.record("Expected instructions entry")
      return
    }
    #expect(instructions.toolDefinitions.map(\.name) == ["lookup"])

    guard case let .prompt(prompt) = entries[1] else {
      Issue.record("Expected prompt entry")
      return
    }
    #expect(prompt.input == "Say hello")

    guard case let .response(recordedResponse) = entries[2] else {
      Issue.record("Expected response entry")
      return
    }
    #expect(recordedResponse.text == "Hello from the engine")
    #expect(recordedResponse.status == .completed)

    let request = try #require(provider.recordedRequests.first)
    #expect(request.instructions == Instructions("Reply briefly"))
    #expect(request.tools.map(\.name) == ["lookup"])
    #expect(request.messages.first?.role == .user)
  }

  @Test func engineRunsMockStructuredOutputTurn() async throws {
    let rawContent = GeneratedContent(properties: ["condition": "sunny", "temperature": 72])
    let provider = ConversationEngineMockProvider(responses: [
      ModelResponse(
        content: rawContent,
        finishReason: .completed,
      ),
    ])
    let engine = ConversationEngine(model: provider)
    let structuredOutput = StructuredOutputRequest(
      format: .generatedContent(
        typeName: "WeatherReport",
        schema: GeneratedContent.generationSchema,
        strict: true,
      ),
      includeSchemaInPrompt: true,
    )

    _ = try await engine.respond(
      prompt: Prompt("Weather in Lisbon?"),
      structuredOutput: structuredOutput,
    )

    guard case let .response(response) = await engine.transcript.entries.last else {
      Issue.record("Expected structured response entry")
      return
    }
    guard case let .structure(segment) = response.segments.first else {
      Issue.record("Expected structured response segment")
      return
    }
    #expect(segment.content == rawContent)

    let request = try #require(provider.recordedRequests.first)
    #expect(request.structuredOutput == structuredOutput)
    guard let promptSegments = request.messages.first?.segments else {
      Issue.record("Expected prompt message")
      return
    }
    #expect(promptSegments.contains { segment in
      guard case let .text(text) = segment else { return false }
      return text.content.contains("Respond with JSON for WeatherReport")
    })
  }

  @Test func engineReducesStreamingTextStructuredDeltasUsageAndCompletion() async throws {
    let provider = ConversationEngineMockProvider(events: [
      .started(ResponseMetadata(id: "stream-1", providerName: "MockProvider")),
      .textStarted(id: "text-1", metadata: nil),
      .textDelta(id: "text-1", delta: "Hel"),
      .textDelta(id: "text-1", delta: "lo"),
      .usage(TokenUsage(outputTokens: 2)),
      .completed(.init(finishReason: .completed)),
    ])
    let engine = ConversationEngine(model: provider)

    var snapshots: [ConversationStreamSnapshot] = []
    let stream = await engine.streamResponse(prompt: Prompt("Stream greeting"))
    for try await snapshot in stream {
      snapshots.append(snapshot)
    }

    #expect(snapshots.count == 6)
    #expect(snapshots.compactMap(\.rawContent).last == GeneratedContent("Hello"))
    #expect(await engine.tokenUsage == TokenUsage(outputTokens: 2))
    #expect(await engine.responseMetadata?.id == "stream-1")

    guard case let .response(response) = await engine.transcript.entries.last else {
      Issue.record("Expected completed response entry")
      return
    }
    #expect(response.text == "Hello")
    #expect(response.status == Transcript.Status.completed)
  }

  @Test func engineReducesStreamingStructuredDeltas() async throws {
    let partialContent = GeneratedContent(properties: ["condition": "sun"])
    let finalContent = GeneratedContent(properties: ["condition": "sunny", "temperature": 72])
    let provider = ConversationEngineMockProvider(events: [
      .structuredDelta(id: "structured-1", delta: partialContent),
      .structuredDelta(id: "structured-1", delta: finalContent),
      .completed(.init(finishReason: .completed)),
    ])
    let engine = ConversationEngine(model: provider)

    var snapshots: [ConversationStreamSnapshot] = []
    let stream = await engine.streamResponse(
      prompt: Prompt("Weather in Lisbon?"),
      structuredOutput: .init(
        format: .generatedContent(
          typeName: "WeatherReport",
          schema: GeneratedContent.generationSchema,
          strict: true,
        ),
      ),
    )
    for try await snapshot in stream {
      snapshots.append(snapshot)
    }

    #expect(snapshots.compactMap(\.rawContent) == [partialContent, finalContent, finalContent])
    guard case let .response(response) = await engine.transcript.entries.last else {
      Issue.record("Expected completed structured response entry")
      return
    }
    guard case let .structure(segment) = response.segments.first else {
      Issue.record("Expected structured segment")
      return
    }
    #expect(segment.content == finalContent)
    #expect(response.status == .completed)
  }

  @Test func engineThrowsWhenProviderStreamFails() async throws {
    let provider = ConversationEngineMockProvider(events: [
      .textStarted(id: "text-1", metadata: nil),
      .textDelta(id: "text-1", delta: "partial"),
      .failed(.init(code: "provider_error", message: "Provider stream failed")),
    ])
    let engine = ConversationEngine(model: provider)

    do {
      let stream = await engine.streamResponse(prompt: Prompt("Stream then fail"))
      for try await _ in stream {}
      Issue.record("Expected stream failure to throw")
    } catch let error as LanguageModelStreamError {
      #expect(error.code == "provider_error")
      #expect(error.message == "Provider stream failed")
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test func engineReducesStreamingToolInputLifecycle() async throws {
    let provider = ConversationEngineMockProvider(events: [
      .toolInputStarted(.init(id: "input-1", callId: "call-1", toolName: "lookup")),
      .toolInputDelta(id: "input-1", delta: "{\"city\":\""),
      .toolInputDelta(id: "input-1", delta: #"Denver"}"#),
      .toolInputCompleted(id: "input-1"),
    ])
    let engine = ConversationEngine(model: provider)

    var snapshots: [ConversationStreamSnapshot] = []
    let stream = await engine.streamResponse(prompt: Prompt("Look up weather"))
    for try await snapshot in stream {
      snapshots.append(snapshot)
    }

    #expect(snapshots.count == 4)
    guard case let .toolCalls(toolCalls) = await engine.transcript.entries.last else {
      Issue.record("Expected tool calls transcript entry")
      return
    }

    let call = try #require(toolCalls.calls.first)
    #expect(call.id == "input-1")
    #expect(call.callId == "call-1")
    #expect(call.toolName == "lookup")
    #expect(call.arguments == GeneratedContent(properties: ["city": "Denver"]))
    #expect(call.partialArguments == nil)
    #expect(call.status == .completed)
  }

  @Test func engineReconcilesToolInputAndCompletedCallByCallID() async throws {
    let completedCall = Transcript.ToolCall(
      id: "tool-1",
      callId: "call-1",
      toolName: "lookup",
      arguments: GeneratedContent(properties: ["city": "Denver"]),
      status: .completed,
    )
    let provider = ConversationEngineMockProvider(events: [
      .toolInputStarted(.init(id: "input-1", callId: "call-1", toolName: "lookup")),
      .toolInputDelta(id: "input-1", delta: "{\"city\":\""),
      .toolInputDelta(id: "input-1", delta: #"Denver"}"#),
      .toolInputCompleted(id: "input-1"),
      .toolCallsCompleted([ModelToolCall(call: completedCall, kind: .local)]),
    ])
    let engine = ConversationEngine(model: provider)

    let stream = await engine.streamResponse(prompt: Prompt("Look up weather"))
    for try await _ in stream {}

    guard case let .toolCalls(toolCalls) = await engine.transcript.entries.last else {
      Issue.record("Expected tool calls transcript entry")
      return
    }

    #expect(toolCalls.calls == [completedCall])
  }

  @Test func engineCancelsProviderStreamWhenConsumerStopsEarly() async throws {
    let provider = CancellationTrackingProvider()
    let engine = ConversationEngine(model: provider)

    var stream: AsyncThrowingStream<ConversationStreamSnapshot, any Error>? =
      await engine.streamResponse(prompt: Prompt("Start and stop"))
    for try await _ in stream! {
      break
    }
    stream = nil

    try await provider.waitForCancellation()
  }

  @Test func enginePreservesProviderMetadataForMockToolTurn() async throws {
    let toolCall = Transcript.ToolCall(
      id: "tool-1",
      callId: "call-1",
      toolName: "lookup",
      arguments: GeneratedContent(properties: ["query": "forecast"]),
      status: .completed,
      providerMetadata: ["mock": .object(["item_id": .string("opaque-function-call")])],
    )
    let provider = ConversationEngineMockProvider(responses: [
      ModelResponse(
        toolCalls: [ModelToolCall(call: toolCall, kind: .local)],
        finishReason: .toolCalls,
      ),
      ModelResponse(
        content: GeneratedContent("Tool result incorporated"),
        finishReason: .completed,
      ),
    ])
    let engine = ConversationEngine(model: provider, tools: [LookupTool()])

    _ = try await engine.respond(prompt: Prompt("Look up the forecast"))

    let output = Transcript.ToolOutput(
      id: "output-1",
      callId: "call-1",
      toolName: "lookup",
      segment: .text(.init(content: "Sunny")),
      status: .completed,
    )
    await engine.recordToolOutputs([output])

    _ = try await engine.respond()

    let requests = provider.recordedRequests
    #expect(requests.count == 2)
    let hasToolCallMetadata = requests[1].messages.contains { message in
      message.role == .assistant && message.providerMetadata["tool_calls"] != nil
    }
    let hasToolOutput = requests[1].messages.contains { message in
      message.role == .tool && message.providerMetadata["call_id"] == JSONValue.string("call-1")
    }
    #expect(hasToolCallMetadata)
    #expect(hasToolOutput)
  }

  @Test func engineProducedTranscriptPreservesPromptGroundingsForSchemaResolution() async throws {
    let provider = ConversationEngineMockProvider(responses: [
      ModelResponse(
        content: GeneratedContent("Grounded response"),
        finishReason: .completed,
      ),
    ])
    let schema = GroundedSchema()
    let date = Date(timeIntervalSince1970: 42)
    let renderedPrompt = Prompt {
      "Current date: \(date)"
      "Question: What day is it?"
    }
    let promptEntry = try Transcript.Prompt(
      input: "What day is it?",
      sources: schema.encodeGrounding([.currentDate(date)]),
      prompt: renderedPrompt.description,
    )
    let engine = ConversationEngine(model: provider)

    _ = try await engine.respond(promptEntry: promptEntry)

    let resolved = try await schema.resolve(engine.transcript)
    let resolvedPrompt = try #require(resolved.compactMap { entry -> Transcript.Resolved<GroundedSchema>.Prompt? in
      guard case let .prompt(prompt) = entry else { return nil }
      return prompt
    }.first)
    #expect(resolvedPrompt.input == "What day is it?")
    #expect(resolvedPrompt.sources == [.currentDate(date)])
    #expect(resolvedPrompt.prompt.contains("Current date:"))
  }
}

private final class ConversationEngineMockProvider: LanguageModel, @unchecked Sendable {
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

private struct LookupTool: Tool {
  let name = "lookup"
  let description = "Looks up a value"

  func call(arguments: GeneratedContent) async throws -> String {
    _ = arguments
    return "lookup result"
  }
}

private final class CancellationTrackingProvider: LanguageModel, @unchecked Sendable {
  typealias UnavailableReason = Never

  private let lock = NSLock()
  private var didCancel = false

  func respond(to request: ModelRequest) async throws -> ModelResponse {
    _ = request
    return ModelResponse(content: GeneratedContent("unused"), finishReason: .completed)
  }

  func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
    _ = request
    return AsyncThrowingStream { continuation in
      let task = Task {
        var counter = 0
        while Task.isCancelled == false {
          continuation.yield(.textDelta(id: "text-1", delta: "event-\(counter)"))
          counter += 1
          try? await Task.sleep(nanoseconds: 10_000_000)
        }
      }
      continuation.onTermination = { _ in
        self.lock.withLock {
          self.didCancel = true
        }
        task.cancel()
      }
    }
  }

  func waitForCancellation() async throws {
    for _ in 0 ..< 100 {
      if lock.withLock({ didCancel }) {
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Expected provider stream to be cancelled")
  }


}
