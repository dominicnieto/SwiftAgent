// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct SessionSchema {}

@Suite("Anthropic - Text")
struct AnthropicTextTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: AnthropicSession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<MessageParameter>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<MessageParameter>(
      recordedResponse: .init(body: textResponse),
    )
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(
      schema: SessionSchema(),
      instructions: "You are helpful.",
      configuration: configuration,
    )
  }

  @Test("Single response")
  func singleResponse() async throws {
    let agentResponse = try await session.respond(
      to: "Hello?",
      using: .claude37SonnetLatest,
    )

    try await validateHTTPRequests()
    validateAgentResponse(agentResponse)
  }

  // MARK: - Private Test Helper Methods

  private func validateHTTPRequests() async throws {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 1)

    let request = recordedRequests[0]
    let json = try requestJSON(from: request.body)

    #expect(json["model"] as? String == AnthropicModel.claude37SonnetLatest.rawValue)
    #expect(json["max_tokens"] as? Int == 1024)
    #expect(json["system"] as? String == "You are helpful.")

    guard let messages = json["messages"] as? [[String: Any]],
          let first = messages.first else {
      Issue.record("Expected messages array in request JSON")
      return
    }

    #expect(first["role"] as? String == "user")
    #expect(first["content"] as? String == "Hello?")
  }

  private func validateAgentResponse(
    _ agentResponse: AgentResponse<String>,
  ) {
    #expect(agentResponse.content == "Hello from Claude")
    #expect(agentResponse.tokenUsage?.totalTokens == 15)

    let generatedTranscript = agentResponse.transcript
    #expect(generatedTranscript.count == 2)

    guard case let .prompt(promptEntry) = generatedTranscript[0] else {
      Issue.record("Expected first transcript entry to be .prompt")
      return
    }

    #expect(promptEntry.input == "Hello?")

    guard case let .response(responseEntry) = generatedTranscript[1] else {
      Issue.record("Expected second transcript entry to be .response")
      return
    }

    #expect(responseEntry.segments.count == 1)
    guard case let .text(textSegment) = responseEntry.segments.first else {
      Issue.record("Expected response segment to be .text")
      return
    }

    #expect(textSegment.content == "Hello from Claude")
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

private let textResponse: String = #"""
{
  "id": "msg_text_1",
  "type": "message",
  "model": "claude-3-7-sonnet-latest",
  "role": "assistant",
  "content": [
    {"type": "text", "text": "Hello from Claude"}
  ],
  "stopReason": "end_turn",
  "stopSequence": null,
  "usage": {
    "inputTokens": 10,
    "outputTokens": 5
  }
}
"""#
