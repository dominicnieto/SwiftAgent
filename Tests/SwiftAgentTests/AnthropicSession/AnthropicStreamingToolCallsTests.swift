// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct SessionSchema {
  @Tool var weather = WeatherTool()
}

@Suite("Anthropic - Streaming - Tool Calls")
struct AnthropicStreamingToolCallsTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: AnthropicSession<SessionSchema>
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
    session = AnthropicSession(schema: SessionSchema(), instructions: "", configuration: configuration)
  }

  @Test("Streaming tool call merges input JSON deltas")
  func streamingToolCallMergesInput() async throws {
    let generatedTranscript = try await processStreamResponse()

    await validateHTTPRequests()
    try validateTranscript(generatedTranscript: generatedTranscript)
  }

  // MARK: - Private Test Helper Methods

  private func processStreamResponse() async throws -> Transcript {
    let stream = try session.streamResponse(
      to: "Weather update",
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
    #expect(toolCalls.calls[0].toolName == "get_weather")

    let expectedArguments = try GeneratedContent(
      json: #"{ "location": "Tokyo", "requestedDate": "2026-01-15", "timeOfDay": "afternoon" }"#,
    )
    #expect(toolCalls.calls[0].arguments.stableJsonString == expectedArguments.stableJsonString)

    guard let toolOutput = firstToolOutput(in: generatedTranscript) else {
      Issue.record("Expected tool output entry")
      return
    }
    guard case let .structure(structuredSegment) = toolOutput.segment else {
      Issue.record("Expected tool output to be structured")
      return
    }

    #expect(structuredSegment.content.generatedContent.kind == .string("Sunny"))

    guard let responseText = lastResponseText(in: generatedTranscript) else {
      Issue.record("Expected response text")
      return
    }

    #expect(responseText == "Done.")
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

  private func lastResponseText(
    in transcript: Transcript,
  ) -> String? {
    var responseText: String?
    for entry in transcript {
      guard case let .response(response) = entry else {
        continue
      }

      responseText = response.text
    }

    return responseText
  }
}

// MARK: - Tool

private struct WeatherTool: FoundationModels.Tool {
  var name: String = "get_weather"
  var description: String = "Get current weather for a given location."

  @Generable
  struct Arguments {
    var location: String
    var requestedDate: String
    var timeOfDay: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}

// MARK: - Mock Responses

private let toolCallResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"id":"msg_tool_1","type":"message","model":"claude-3-7-sonnet-latest","role":"assistant","content":[],"stopReason":null,"stopSequence":null,"usage":{"inputTokens":8,"outputTokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_weather_1","name":"get_weather","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partialJson":"{\"location\": \"Tokyo\", \"requestedDate\": \"2026-01-15\", \"timeOfDay\": \"afternoon\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stopReason":"tool_use","stopSequence":null},"usage":{"inputTokens":8,"outputTokens":2}}

event: message_stop
data: {"type":"message_stop"}
"""#

private let finalResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"id":"msg_final_1","type":"message","model":"claude-3-7-sonnet-latest","role":"assistant","content":[],"stopReason":null,"stopSequence":null,"usage":{"inputTokens":12,"outputTokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Done."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stopReason":"end_turn","stopSequence":null},"usage":{"inputTokens":12,"outputTokens":2}}

event: message_stop
data: {"type":"message_stop"}
"""#
