import Foundation
import Testing

@testable import SwiftAgent

@Suite("Model turn contract")
struct ModelTurnContractTests {
  @Test func modelRequestRoundTripsThroughCodable() throws {
    let request = ModelRequest(
      messages: [
        ModelMessage(
          role: .user,
          segments: [.text(.init(content: "Hello"))],
          providerMetadata: ["message_id": .string("msg-1")],
        ),
      ],
      instructions: Instructions("Reply briefly"),
      tools: [
        ToolDefinition(
          name: "lookup",
          description: "Looks up a value",
          schema: GeneratedContent.generationSchema,
          providerMetadata: .object(["provider_kind": .string("function")]),
        ),
      ],
      toolChoice: .named("lookup"),
      structuredOutput: .init(
        format: .generatedContent(
          typeName: "Answer",
          schema: GeneratedContent.generationSchema,
          strict: true,
        ),
        includeSchemaInPrompt: false,
      ),
      generationOptions: GenerationOptions(temperature: 0.2, maximumResponseTokens: 128),
      attachments: [
        ModelAttachment(kind: .image, mimeType: "image/png", url: URL(string: "https://example.com/image.png")),
      ],
    )

    let encoded = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(ModelRequest.self, from: encoded)

    #expect(decoded == request)
  }

  @Test func modelResponseRoundTripsThroughCodable() throws {
    let response = ModelResponse(
      content: GeneratedContent("Done"),
      transcriptEntries: [
        .response(.init(segments: [.text(.init(content: "Done"))])),
      ],
      toolCalls: [
        ModelToolCall(
          call: Transcript.ToolCall(
            id: "provider-tool-1",
            callId: "provider-call-1",
            toolName: "web_search",
            arguments: GeneratedContent(properties: ["query": "weather"]),
            status: .completed,
            providerMetadata: ["mock": .object(["item_id": .string("tool-item-1")])],
          ),
          kind: .providerDefined,
          providerMetadata: ["provider_tool": .string("web_search_preview")],
        ),
      ],
      finishReason: .completed,
      tokenUsage: TokenUsage(inputTokens: 4, outputTokens: 2, totalTokens: 6),
      responseMetadata: ResponseMetadata(
        id: "response-1",
        providerName: "MockProvider",
        modelID: "mock-model",
        providerMetadata: ["mock": .object(["response_id": .string("response-1")])],
      ),
      rawProviderOutput: .object(["id": .string("response-1")]),
    )

    let encoded = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(ModelResponse.self, from: encoded)

    #expect(decoded == response)
  }

  @Test func streamEventsPreserveRichLifecycleValues() {
    let toolCall = Transcript.ToolCall(
      id: "tool-1",
      callId: "call-1",
      toolName: "lookup",
      arguments: GeneratedContent(properties: ["query": "weather"]),
      status: .completed,
      providerMetadata: ["provider_tool": .string("search")],
    )
    let modelToolCall = ModelToolCall(
      call: toolCall,
      kind: .providerDefined,
      providerMetadata: ["provider_tool": .string("search")],
    )

    let events: [ModelStreamEvent] = [
      .started(ResponseMetadata(id: "response-1")),
      .warnings([
        LanguageModelWarning(
          code: "rate_limit_near",
          message: "Approaching rate limit",
          providerMetadata: ["remaining": .double(2)],
        ),
      ]),
      .textStarted(id: "text-1", metadata: nil),
      .textDelta(id: "text-1", delta: "Hel"),
      .textCompleted(id: "text-1", metadata: nil),
      .structuredDelta(id: "structured-1", delta: GeneratedContent(properties: ["status": "partial"])),
      .reasoningStarted(id: "reasoning-1", metadata: nil),
      .reasoningDelta(id: "reasoning-1", delta: "summary"),
      .reasoningCompleted(.init(
        id: "reasoning-1",
        summary: ["summary"],
        encryptedReasoning: "encrypted",
        status: .completed,
      )),
      .toolInputStarted(.init(
        id: "input-1",
        callId: "call-1",
        toolName: "lookup",
        kind: .providerDefined,
        providerMetadata: ["provider_tool": .string("search")],
      )),
      .toolInputDelta(id: "input-1", delta: #"{"query":"weather"}"#),
      .toolCallPartial(.init(
        id: "input-1",
        callId: "call-1",
        toolName: "lookup",
        partialArguments: #"{"query":"weather"}"#,
        arguments: GeneratedContent(properties: ["query": "weather"]),
        kind: .providerDefined,
        providerMetadata: ["provider_tool": .string("search")],
      )),
      .toolInputCompleted(id: "input-1"),
      .toolCallsCompleted([modelToolCall]),
      .providerToolResult(.init(
        id: "output-1",
        callId: "call-1",
        toolName: "lookup",
        segment: .text(.init(content: "72F")),
        status: .completed,
      )),
      .source(.init(id: "source-1", title: "Forecast", url: "https://example.com")),
      .file(.init(id: "file-1", filename: "result.json", mimeType: "application/json")),
      .usage(TokenUsage(outputTokens: 3)),
      .metadata(ResponseMetadata(providerName: "MockProvider")),
      .completed(.init(finishReason: .toolCalls)),
      .failed(.init(
        code: "stream_closed",
        message: "Stream closed by provider",
        providerMetadata: ["retryable": .bool(false)],
      )),
      .raw(.object(["event": .string("done")])),
    ]

    #expect(events.count == 22)

    guard case let .started(metadata) = events[0] else {
      Issue.record("Expected stream start event")
      return
    }
    #expect(metadata?.id == "response-1")

    guard case let .warnings(warnings) = events[1] else {
      Issue.record("Expected warning event")
      return
    }
    #expect(warnings.first?.code == "rate_limit_near")
    #expect(warnings.first?.providerMetadata["remaining"] == .double(2))

    guard case let .textDelta(id, delta) = events[3] else {
      Issue.record("Expected text delta event")
      return
    }
    #expect(id == "text-1")
    #expect(delta == "Hel")

    guard case let .structuredDelta(id, delta) = events[5] else {
      Issue.record("Expected structured delta event")
      return
    }
    #expect(id == "structured-1")
    #expect(delta == GeneratedContent(properties: ["status": "partial"]))

    guard case let .reasoningCompleted(reasoning) = events[8] else {
      Issue.record("Expected reasoning completion event")
      return
    }
    #expect(reasoning.id == "reasoning-1")
    #expect(reasoning.summary == ["summary"])
    #expect(reasoning.encryptedReasoning == "encrypted")
    #expect(reasoning.status == .completed)

    guard case let .toolInputStarted(inputStart) = events[9] else {
      Issue.record("Expected tool input start event")
      return
    }
    #expect(inputStart.id == "input-1")
    #expect(inputStart.callId == "call-1")
    #expect(inputStart.toolName == "lookup")
    #expect(inputStart.kind == .providerDefined)
    #expect(inputStart.providerMetadata["provider_tool"] == .string("search"))

    guard case let .toolCallPartial(partial) = events[11] else {
      Issue.record("Expected partial tool call event")
      return
    }
    #expect(partial.id == "input-1")
    #expect(partial.callId == "call-1")
    #expect(partial.toolName == "lookup")
    #expect(partial.partialArguments == #"{"query":"weather"}"#)
    #expect(partial.arguments == GeneratedContent(properties: ["query": "weather"]))
    #expect(partial.kind == .providerDefined)

    guard case let .toolCallsCompleted(completedCalls) = events[13] else {
      Issue.record("Expected completed tool calls event")
      return
    }
    #expect(completedCalls == [modelToolCall])
    #expect(completedCalls.first?.call == toolCall)
    #expect(completedCalls.first?.kind == .providerDefined)
    #expect(completedCalls.first?.providerMetadata["provider_tool"] == JSONValue.string("search"))

    guard case let .providerToolResult(toolOutput) = events[14] else {
      Issue.record("Expected provider tool result event")
      return
    }
    #expect(toolOutput.callId == "call-1")
    #expect(toolOutput.toolName == "lookup")
    #expect(toolOutput.status == .completed)
    guard case let .text(outputText) = toolOutput.segment else {
      Issue.record("Expected text tool output segment")
      return
    }
    #expect(outputText.content == "72F")

    guard case let .source(source) = events[15] else {
      Issue.record("Expected source event")
      return
    }
    #expect(source.id == "source-1")
    #expect(source.title == "Forecast")
    #expect(source.url == "https://example.com")

    guard case let .file(file) = events[16] else {
      Issue.record("Expected file event")
      return
    }
    #expect(file.id == "file-1")
    #expect(file.filename == "result.json")
    #expect(file.mimeType == "application/json")

    guard case let .usage(usage) = events[17] else {
      Issue.record("Expected usage event")
      return
    }
    #expect(usage.outputTokens == 3)

    guard case let .metadata(metadata) = events[18] else {
      Issue.record("Expected metadata event")
      return
    }
    #expect(metadata.providerName == "MockProvider")

    guard case let .completed(completion) = events[19] else {
      Issue.record("Expected completion event")
      return
    }
    #expect(completion.finishReason == .toolCalls)

    guard case let .failed(error) = events[20] else {
      Issue.record("Expected failure event")
      return
    }
    #expect(error.code == "stream_closed")
    #expect(error.message == "Stream closed by provider")
    #expect(error.providerMetadata["retryable"] == .bool(false))

    guard case let .raw(rawEvent) = events[21] else {
      Issue.record("Expected raw event")
      return
    }
    #expect(rawEvent == .object(["event": .string("done")]))
  }

  @Test func mockProviderCompilesAgainstNeutralTurnAPI() async throws {
    let expected = ModelResponse(
      content: GeneratedContent("Hello"),
      finishReason: .completed,
      tokenUsage: TokenUsage(inputTokens: 1, outputTokens: 1, totalTokens: 2),
    )
    let provider = ModelTurnMockProvider(response: expected, events: [
      .textDelta(id: "text-1", delta: "Hello"),
      .completed(.init(finishReason: .completed)),
    ])
    let request = ModelRequest(messages: [
      ModelMessage(role: .user, segments: [.text(.init(content: "Say hello"))]),
    ])

    let response = try await provider.respond(to: request)
    #expect(response == expected)

    var streamedEvents: [ModelStreamEvent] = []
    for try await event in provider.streamResponse(to: request) {
      streamedEvents.append(event)
    }

    #expect(streamedEvents == provider.events)
  }
}

private struct ModelTurnMockProvider: LanguageModel {
  typealias UnavailableReason = Never

  var response: ModelResponse
  var events: [ModelStreamEvent]

  func respond(to request: ModelRequest) async throws -> ModelResponse {
    _ = request
    return response
  }

  func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
    _ = request
    let events = events
    return AsyncThrowingStream { continuation in
      for event in events {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }


}
