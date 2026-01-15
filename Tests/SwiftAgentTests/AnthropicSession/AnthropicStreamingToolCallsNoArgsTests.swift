// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct NoArgsSessionSchema {
  @Tool var ping = PingTool()
}

@Suite("Anthropic - Streaming - Tool Calls (No Args)")
struct AnthropicStreamingToolCallsNoArgsTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: AnthropicSession<NoArgsSessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<MessageParameter>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<MessageParameter>(
      recordedResponses: [
        .init(body: toolCallResponse),
        .init(body: finalResponse),
      ],
    )
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(schema: NoArgsSessionSchema(), instructions: "", configuration: configuration)
  }

  @Test("Executes tool call with empty arguments")
  func executesToolCallWithEmptyArguments() async throws {
    let generatedTranscript = try await processStreamResponse()

    await validateHTTPRequests()
    try validateTranscript(generatedTranscript: generatedTranscript)
  }

  // MARK: - Private Test Helper Methods

  private func processStreamResponse() async throws -> Transcript {
    let stream = try session.streamResponse(
      to: "Ping",
      using: .claude37SonnetLatest,
    )

    var generatedTranscript = Transcript()

    for try await snapshot in stream {
      generatedTranscript = snapshot.transcript
    }

    return generatedTranscript
  }

  private func validateHTTPRequests() async {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 2)
  }

  private func validateTranscript(generatedTranscript: Transcript) throws {
    guard let toolCalls = firstToolCalls(in: generatedTranscript) else {
      Issue.record("Expected tool call entry")
      return
    }

    #expect(toolCalls.calls.count == 1)
    #expect(toolCalls.calls[0].toolName == "ping")

    let expectedArguments = try GeneratedContent(json: #"{}"#)
    #expect(toolCalls.calls[0].arguments.stableJsonString == expectedArguments.stableJsonString)

    guard let toolOutput = firstToolOutput(in: generatedTranscript) else {
      Issue.record("Expected tool output entry")
      return
    }
    guard case let .structure(structuredSegment) = toolOutput.segment else {
      Issue.record("Expected tool output to be structured")
      return
    }

    #expect(structuredSegment.content.generatedContent.kind == .string("pong"))
  }

  private func firstToolCalls(
    in transcript: Transcript,
  ) -> Transcript.ToolCalls? {
    for entry in transcript {
      guard case let .toolCalls(toolCalls) = entry else {
        continue
      }

      return toolCalls
    }

    return nil
  }

  private func firstToolOutput(
    in transcript: Transcript,
  ) -> Transcript.ToolOutput? {
    for entry in transcript {
      guard case let .toolOutput(toolOutput) = entry else {
        continue
      }

      return toolOutput
    }

    return nil
  }
}

// MARK: - Tool

private struct PingTool: FoundationModels.Tool {
  var name: String = "ping"
  var description: String = "Returns pong with no arguments."

  @Generable
  struct Arguments {
    var placeholder: String?
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "pong"
  }
}

// MARK: - Mock Responses

private let toolCallResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"id":"msg_ping_1","type":"message","model":"claude-3-7-sonnet-latest","role":"assistant","content":[],"stopReason":null,"stopSequence":null,"usage":{"inputTokens":4,"outputTokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_ping_1","name":"ping","input":{}}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stopReason":"tool_use","stopSequence":null},"usage":{"inputTokens":4,"outputTokens":2}}

event: message_stop
data: {"type":"message_stop"}
"""#

private let finalResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"id":"msg_ping_final","type":"message","model":"claude-3-7-sonnet-latest","role":"assistant","content":[],"stopReason":null,"stopSequence":null,"usage":{"inputTokens":6,"outputTokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"pong"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stopReason":"end_turn","stopSequence":null},"usage":{"inputTokens":6,"outputTokens":2}}

event: message_stop
data: {"type":"message_stop"}
"""#
