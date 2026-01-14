// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct SessionSchema {}

@Suite("Anthropic - Streaming - Text")
struct AnthropicStreamingTextTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: AnthropicSession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<MessageParameter>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<MessageParameter>(
      recordedResponse: .init(body: streamingResponse),
    )
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(schema: SessionSchema(), instructions: "", configuration: configuration)
  }

  @Test("Single streamed response")
  func singleResponse() async throws {
    let (generatedTranscript, latestContent) = try await processStreamResponse()

    await validateHTTPRequests()
    try validateTranscript(generatedTranscript: generatedTranscript)
    #expect(latestContent == "Hello")
  }

  // MARK: - Private Test Helper Methods

  private func processStreamResponse() async throws -> (Transcript, String?) {
    let stream = try session.streamResponse(
      to: "prompt",
      using: .claude37SonnetLatest,
    )

    var generatedTranscript = Transcript()
    var latestContent: String?

    for try await snapshot in stream {
      generatedTranscript = snapshot.transcript
      if let content = snapshot.content {
        latestContent = content
      }
    }

    return (generatedTranscript, latestContent)
  }

  private func validateHTTPRequests() async {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 1)

    let request = recordedRequests[0]
    let json = try? requestJSON(from: request.body)

    #expect(json?["stream"] as? Bool == true)
    #expect(json?["model"] as? String == AnthropicModel.claude37SonnetLatest.rawValue)
  }

  private func validateTranscript(generatedTranscript: Transcript) throws {
    #expect(generatedTranscript.count == 2)

    guard case let .prompt(prompt) = generatedTranscript[0] else {
      Issue.record("First transcript entry is not .prompt")
      return
    }

    #expect(prompt.input == "prompt")

    guard case let .response(response) = generatedTranscript[1] else {
      Issue.record("Second transcript entry is not .response")
      return
    }

    #expect(response.segments.count == 1)
    guard case let .text(textSegment) = response.segments.first else {
      Issue.record("Second transcript entry is not .text")
      return
    }

    #expect(textSegment.content == "Hello")
  }

  private func requestJSON(
    from request: MessageParameter,
  ) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let data = try encoder.encode(request)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let json = object as? [String: Any] else {
      throw GenerationError.requestFailed(
        reason: .decodingFailure,
        detail: "Failed to decode request JSON",
      )
    }

    return json
  }
}

// MARK: - Mock Responses

private let streamingResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"id":"msg_stream_1","type":"message","model":"claude-3-7-sonnet-latest","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":4,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":4,"output_tokens":2}}

event: message_stop
data: {"type":"message_stop"}
"""#
