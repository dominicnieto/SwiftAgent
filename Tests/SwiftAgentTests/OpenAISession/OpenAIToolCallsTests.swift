// By Dennis Müller

import Foundation
import OpenAI
@testable import OpenAISession
@testable import SwiftAgent
import Testing

@SessionSchema
private struct SessionSchema {
  @Tool var weather = WeatherTool()
}

@Suite("OpenAI - Tool Calls")
struct OpenAIToolCallsTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: OpenAISession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<CreateModelResponseQuery>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<CreateModelResponseQuery>(
      recordedResponses: [
        .init(body: toolCallResponse),
        .init(body: finalResponse),
      ],
    )

    let configuration = OpenAIConfiguration(httpClient: mockHTTPClient)
    session = OpenAISession(
      schema: SessionSchema(),
      instructions: """
      Always call `get_weather` exactly once before answering.
      Call it with exactly: { "location": "New York City, USA" }.
      After tool output, reply with exactly: Done.
      """,
      configuration: configuration,
    )
  }

  @Test("Non-streaming tool call executes and continues to final response")
  func nonStreamingToolCallExecutesAndContinues() async throws {
    let response = try await session.respond(
      to: "What is the weather in New York City, USA?",
      using: .gpt4o,
    )

    await validateHTTPRequests()
    try validateAgentResponse(response)
  }

  // MARK: - Private

  private func validateHTTPRequests() async {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 2)

    // First request: user prompt only.
    do {
      let request = recordedRequests[0]

      guard case let .inputItemList(items) = request.body.input else {
        Issue.record("First request body input is not .inputItemList")
        return
      }

      #expect(items.count == 1)

      guard case let .inputMessage(message) = items[0] else {
        Issue.record("First request first item is not .inputMessage")
        return
      }
      guard case let .textInput(text) = message.content else {
        Issue.record("Expected first request message content to be .textInput")
        return
      }

      #expect(text == "What is the weather in New York City, USA?")
    }

    // Second request: prompt + tool call + tool output.
    do {
      let request = recordedRequests[1]

      guard case let .inputItemList(items) = request.body.input else {
        Issue.record("Second request body input is not .inputItemList")
        return
      }

      #expect(items.count == 3)

      guard case let .inputMessage(message) = items[0] else {
        Issue.record("Second request first item is not .inputMessage")
        return
      }
      guard case let .textInput(text) = message.content else {
        Issue.record("Expected second request message content to be .textInput")
        return
      }

      #expect(text == "What is the weather in New York City, USA?")

      guard case let .item(.functionToolCall(functionCall)) = items[1] else {
        Issue.record("Second request second item is not .functionToolCall")
        return
      }

      #expect(functionCall.id == "fc_0cfebcfb17a1bae1016968da286ac88197b6f649d0a48de552")
      #expect(functionCall.callId == "call_scDlmjxmPWh2nmefVK1WexmU")
      #expect(functionCall.name == "get_weather")
      #expect(functionCall.arguments == #"{"location":"New York City, USA"}"#)

      guard case let .item(.functionCallOutputItemParam(functionOutput)) = items[2] else {
        Issue.record("Second request third item is not .functionCallOutputItemParam")
        return
      }

      #expect(functionOutput.callId == "call_scDlmjxmPWh2nmefVK1WexmU")
      #expect(functionOutput.output == "\"Sunny\"")
    }
  }

  private func validateAgentResponse(
    _ response: AgentResponse<String>,
  ) throws {
    #expect(response.content == "Done.")
    #expect(response.tokenUsage?.totalTokens == 242)

    let transcript = response.transcript
    #expect(transcript.count == 4)

    guard case let .prompt(promptEntry) = transcript[0] else {
      Issue.record("Expected first transcript entry to be .prompt")
      return
    }

    #expect(promptEntry.input == "What is the weather in New York City, USA?")

    guard case let .toolCalls(toolCallsEntry) = transcript[1] else {
      Issue.record("Expected second transcript entry to be .toolCalls")
      return
    }

    #expect(toolCallsEntry.calls.count == 1)
    let toolCall = toolCallsEntry.calls[0]
    #expect(toolCall.id == "fc_0cfebcfb17a1bae1016968da286ac88197b6f649d0a48de552")
    #expect(toolCall.callId == "call_scDlmjxmPWh2nmefVK1WexmU")
    #expect(toolCall.toolName == "get_weather")

    let expectedArguments = try GeneratedContent(json: #"{ "location": "New York City, USA" }"#)
    #expect(toolCall.arguments.stableJsonString == expectedArguments.stableJsonString)

    guard case let .toolOutput(toolOutputEntry) = transcript[2] else {
      Issue.record("Expected third transcript entry to be .toolOutput")
      return
    }

    #expect(toolOutputEntry.id == "fc_0cfebcfb17a1bae1016968da286ac88197b6f649d0a48de552")
    #expect(toolOutputEntry.callId == "call_scDlmjxmPWh2nmefVK1WexmU")
    #expect(toolOutputEntry.toolName == "get_weather")

    guard case let .structure(structuredSegment) = toolOutputEntry.segment else {
      Issue.record("Expected tool output segment to be .structure")
      return
    }

    #expect(structuredSegment.content.generatedContent.kind == .string("Sunny"))

    guard case let .response(responseEntry) = transcript[3] else {
      Issue.record("Expected fourth transcript entry to be .response")
      return
    }

    #expect(responseEntry.segments.count == 1)

    guard case let .text(textSegment) = responseEntry.segments.first else {
      Issue.record("Expected response segment to be .text")
      return
    }

    #expect(textSegment.content == "Done.")
  }
}

// MARK: - Tool

private struct WeatherTool: SwiftAgent.Tool {
  var name: String = "get_weather"
  var description: String = "Get current temperature for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}

// MARK: - Fixtures

private let toolCallResponse: String = #"""
{
  "background" : false,
  "billing" : {
    "payer" : "openai"
  },
  "completed_at" : 1768479272,
  "created_at" : 1768479271,
  "error" : null,
  "frequency_penalty" : 0,
  "id" : "resp_0cfebcfb17a1bae1016968da274a288197a24fa63f5e631c63",
  "incomplete_details" : null,
  "instructions" : "Always call `get_weather` exactly once before answering.\nCall it with exactly: { \"location\": \"New York City, USA\" }.\nAfter tool output, reply with exactly: Done.",
  "max_output_tokens" : null,
  "max_tool_calls" : null,
  "metadata" : {

  },
  "model" : "gpt-4o-2024-08-06",
  "object" : "response",
  "output" : [
    {
      "arguments" : "{\"location\":\"New York City, USA\"}",
      "call_id" : "call_scDlmjxmPWh2nmefVK1WexmU",
      "id" : "fc_0cfebcfb17a1bae1016968da286ac88197b6f649d0a48de552",
      "name" : "get_weather",
      "status" : "completed",
      "type" : "function_call"
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
    {
      "description" : "Get current temperature for a given location.",
      "name" : "get_weather",
      "parameters" : {
        "additionalProperties" : false,
        "properties" : {
          "location" : {
            "type" : "string"
          }
        },
        "required" : [
          "location"
        ],
        "title" : "Arguments",
        "type" : "object",
        "x-order" : [
          "location"
        ]
      },
      "strict" : false,
      "type" : "function"
    }
  ],
  "top_logprobs" : 0,
  "top_p" : 1,
  "truncation" : "disabled",
  "usage" : {
    "input_tokens" : 96,
    "input_tokens_details" : {
      "cached_tokens" : 0
    },
    "output_tokens" : 19,
    "output_tokens_details" : {
      "reasoning_tokens" : 0
    },
    "total_tokens" : 115
  },
  "user" : null
}
"""#

private let finalResponse: String = #"""
{
  "background" : false,
  "billing" : {
    "payer" : "openai"
  },
  "completed_at" : 1768479274,
  "created_at" : 1768479273,
  "error" : null,
  "frequency_penalty" : 0,
  "id" : "resp_0cfebcfb17a1bae1016968da2925108197a387858aedc4d51b",
  "incomplete_details" : null,
  "instructions" : "Always call `get_weather` exactly once before answering.\nCall it with exactly: { \"location\": \"New York City, USA\" }.\nAfter tool output, reply with exactly: Done.",
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
          "text" : "Done.",
          "type" : "output_text"
        }
      ],
      "id" : "msg_0cfebcfb17a1bae1016968da2aba108197ac4e6444549365da",
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
    {
      "description" : "Get current temperature for a given location.",
      "name" : "get_weather",
      "parameters" : {
        "additionalProperties" : false,
        "properties" : {
          "location" : {
            "type" : "string"
          }
        },
        "required" : [
          "location"
        ],
        "title" : "Arguments",
        "type" : "object",
        "x-order" : [
          "location"
        ]
      },
      "strict" : false,
      "type" : "function"
    }
  ],
  "top_logprobs" : 0,
  "top_p" : 1,
  "truncation" : "disabled",
  "usage" : {
    "input_tokens" : 123,
    "input_tokens_details" : {
      "cached_tokens" : 0
    },
    "output_tokens" : 4,
    "output_tokens_details" : {
      "reasoning_tokens" : 0
    },
    "total_tokens" : 127
  },
  "user" : null
}
"""#
