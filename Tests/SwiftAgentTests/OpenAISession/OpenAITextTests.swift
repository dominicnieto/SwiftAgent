// By Dennis Müller

import Foundation
import OpenAI
@testable import OpenAISession
@testable import SwiftAgent
import Testing

@SessionSchema
private struct SessionSchema {}

@Suite("OpenAI - Text")
struct OpenAITextTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: OpenAISession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<CreateModelResponseQuery>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<CreateModelResponseQuery>(
      recordedResponse: .init(body: helloFromOpenAIResponse),
    )

    let configuration = OpenAIConfiguration(httpClient: mockHTTPClient)
    session = OpenAISession(
      schema: SessionSchema(),
      instructions: "Reply with exactly: Hello from OpenAI",
      configuration: configuration,
    )
  }

  @Test("Non-streaming respond returns text content + transcript")
  func respondReturnsTextContentAndTranscript() async throws {
    let response = try await session.respond(
      to: "Hello?",
      using: .gpt4o,
    )

    await validateHTTPRequests()
    validateAgentResponse(response)
  }

  // MARK: - Private

  private func validateHTTPRequests() async {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 1)

    let request = recordedRequests[0]

    #expect(request.body.model == OpenAIModel.gpt4o.rawValue)
    #expect(request.body.instructions == "Reply with exactly: Hello from OpenAI")

    guard case let .inputItemList(items) = request.body.input else {
      Issue.record("Recorded request body input is not .inputItemList")
      return
    }

    #expect(items.count == 1)

    guard case let .inputMessage(message) = items[0] else {
      Issue.record("Recorded request body input item is not .inputMessage")
      return
    }
    guard case let .textInput(text) = message.content else {
      Issue.record("Expected message content to be .textInput")
      return
    }

    #expect(text == "Hello?")
  }

  private func validateAgentResponse(
    _ response: AgentResponse<String>,
  ) {
    #expect(response.content == "Hello from OpenAI")
    #expect(response.tokenUsage?.totalTokens == 26)

    let transcript = response.transcript
    #expect(transcript.count == 2)

    guard case let .prompt(promptEntry) = transcript[0] else {
      Issue.record("Expected first transcript entry to be .prompt")
      return
    }

    #expect(promptEntry.input == "Hello?")

    guard case let .response(responseEntry) = transcript[1] else {
      Issue.record("Expected second transcript entry to be .response")
      return
    }

    #expect(responseEntry.segments.count == 1)

    guard case let .text(textSegment) = responseEntry.segments.first else {
      Issue.record("Expected response segment to be .text")
      return
    }

    #expect(textSegment.content == "Hello from OpenAI")
  }
}

// MARK: - Fixture

private let helloFromOpenAIResponse: String = #"""
{
  "background" : false,
  "billing" : {
    "payer" : "openai"
  },
  "completed_at" : 1768479259,
  "created_at" : 1768479259,
  "error" : null,
  "frequency_penalty" : 0,
  "id" : "resp_0e0af2f860d43793016968da1b18808194b60c8c90c3e23c61",
  "incomplete_details" : null,
  "instructions" : "Reply with exactly: Hello from OpenAI",
  "max_output_tokens" : null,
  "max_tool_calls" : null,
  "metadata" : {

  },
  "model" : "gpt-4o-2024-08-06",
  "object" : "response",
  "output" : [
    {
      "content" : [
        {
          "annotations" : [

          ],
          "logprobs" : [

          ],
          "text" : "Hello from OpenAI",
          "type" : "output_text"
        }
      ],
      "id" : "msg_0e0af2f860d43793016968da1be3288194a6c733707d17f475",
      "role" : "assistant",
      "status" : "completed",
      "type" : "message"
    }
  ],
  "parallel_tool_calls" : true,
  "presence_penalty" : 0,
  "previous_response_id" : null,
  "prompt_cache_key" : null,
  "prompt_cache_retention" : null,
  "reasoning" : {
    "effort" : null,
    "summary" : null
  },
  "safety_identifier" : null,
  "service_tier" : "default",
  "status" : "completed",
  "store" : false,
  "temperature" : 1,
  "text" : {
    "format" : {
      "type" : "text"
    },
    "verbosity" : "medium"
  },
  "tool_choice" : "auto",
  "tools" : [

  ],
  "top_logprobs" : 0,
  "top_p" : 1,
  "truncation" : "disabled",
  "usage" : {
    "input_tokens" : 21,
    "input_tokens_details" : {
      "cached_tokens" : 0
    },
    "output_tokens" : 5,
    "output_tokens_details" : {
      "reasoning_tokens" : 0
    },
    "total_tokens" : 26
  },
  "user" : null
}
"""#
