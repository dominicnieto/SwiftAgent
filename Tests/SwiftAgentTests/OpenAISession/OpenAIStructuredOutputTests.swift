// By Dennis Müller

import Foundation
import OpenAI
@testable import OpenAISession
@testable import SwiftAgent
import Testing

@SessionSchema
private struct SessionSchema {
  @StructuredOutput(WeatherForecast.self) var weatherForecast
}

@Suite("OpenAI - Structured Output")
struct OpenAIStructuredOutputTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: OpenAISession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<CreateModelResponseQuery>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<CreateModelResponseQuery>(
      recordedResponse: .init(body: structuredOutputResponse),
    )
    let configuration = OpenAIConfiguration(httpClient: mockHTTPClient)
    session = OpenAISession(schema: SessionSchema(), instructions: "", configuration: configuration)
  }

  @Test("Structured response is decoded into WeatherForecast")
  func structuredResponseIsDecoded() async throws {
    let agentResponse = try await performStructuredResponse()

    try await validateHTTPRequests()
    validateAgentResponse(agentResponse)
  }

  // MARK: - Private Test Helper Methods

  private func performStructuredResponse() async throws -> AgentResponse<WeatherForecast> {
    try await session.respond(
      to: "Provide the latest weather update.",
      generating: WeatherForecast.self,
      using: .other("gpt-5.2-2025-12-11", isReasoning: true),
      options: .init(
        include: [.reasoning_encryptedContent],
        reasoning: .init(
          effort: .low,
          summary: .detailed,
        ),
      ),
    )
  }

  private func validateHTTPRequests() async throws {
    let recordedRequests = await mockHTTPClient.recordedRequests()

    let request = try #require(recordedRequests.first)
    guard case let .inputItemList(items) = request.body.input else {
      Issue.record("Recorded request body input is not .inputItemList")
      return
    }

    #expect(items.count == 1)

    guard case let .inputMessage(message) = items[0] else {
      Issue.record("Recorded request item is not .inputMessage")
      return
    }
    guard case let .textInput(text) = message.content else {
      Issue.record("Expected message content to be text input")
      return
    }

    #expect(text == "Provide the latest weather update.")

    let expectedOutputConfig = CreateModelResponseQuery.TextResponseConfigurationOptions.OutputFormat
      .StructuredOutputsConfig(
        name: WeatherForecast.name,
        schema: .dynamicJsonSchema(WeatherForecast.Schema.generationSchema),
        description: nil,
        strict: false,
      )

    guard request.body.text == .jsonSchema(expectedOutputConfig) else {
      Issue.record("Expected text configuration format to be present")
      return
    }
  }

  private func validateAgentResponse(_ agentResponse: AgentResponse<WeatherForecast>) {
    #expect(agentResponse.content.temperatureCelsius == 22)
    #expect(agentResponse.content.condition == "Partly Cloudy")
    #expect(agentResponse.tokenUsage?.totalTokens == 99)

    let generatedTranscript = agentResponse.transcript
    #expect(generatedTranscript.count == 2)

    guard case let .prompt(promptEntry) = generatedTranscript[0] else {
      Issue.record("Expected first transcript entry to be .prompt")
      return
    }

    #expect(promptEntry.input == "Provide the latest weather update.")

    guard case let .response(responseEntry) = generatedTranscript[1] else {
      Issue.record("Expected second transcript entry to be .response")
      return
    }

    #expect(responseEntry.segments.count == 1)
    guard case let .structure(structuredSegment) = responseEntry.segments.first else {
      Issue.record("Expected response segment to be .structure")
      return
    }

    #expect(structuredSegment.typeName == WeatherForecast.name)

    do {
      let decodedForecast = try WeatherForecast.Schema(structuredSegment.content)
      #expect(decodedForecast.temperatureCelsius == agentResponse.content.temperatureCelsius)
      #expect(decodedForecast.condition == agentResponse.content.condition)
    } catch {
      Issue.record("Failed to decode structured segment: \(error)")
    }
  }
}

private struct WeatherForecast: StructuredOutput {
  static let name: String = "weather_forecast"

  @Generable
  struct Schema {
    var temperatureCelsius: Double
    var condition: String
  }
}

// MARK: - Mock Responses

private let structuredOutputResponse: String = #"""
{
  "background" : false,
  "billing" : {
    "payer" : "openai"
  },
  "completed_at" : 1768475136,
  "created_at" : 1768475135,
  "error" : null,
  "frequency_penalty" : 0,
  "id" : "resp_08b81f318881f31f016968c9ff71c88197984cccfad9337ef9",
  "incomplete_details" : null,
  "instructions" : "Return temperatureCelsius=22 and condition=Partly Cloudy.",
  "max_output_tokens" : null,
  "max_tool_calls" : null,
  "metadata" : {

  },
  "model" : "gpt-5.2-2025-12-11",
  "object" : "response",
  "output" : [
    {
      "content" : [
        {
          "annotations" : [

          ],
          "logprobs" : [

          ],
          "text" : "{\"temperatureCelsius\":22,\"condition\":\"Partly Cloudy\"}",
          "type" : "output_text"
        }
      ],
      "id" : "msg_08b81f318881f31f016968c9ffe4548197be207169e4ef3d3e",
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
    "effort" : "low",
    "summary" : "detailed"
  },
  "safety_identifier" : null,
  "service_tier" : "default",
  "status" : "completed",
  "store" : false,
  "temperature" : 1,
  "text" : {
    "format" : {
      "description" : null,
      "name" : "weather_forecast",
      "schema" : {
        "additionalProperties" : false,
        "properties" : {
          "condition" : {
            "type" : "string"
          },
          "temperatureCelsius" : {
            "type" : "number"
          }
        },
        "required" : [
          "temperatureCelsius",
          "condition"
        ],
        "title" : "Schema",
        "type" : "object",
        "x-order" : [
          "temperatureCelsius",
          "condition"
        ]
      },
      "strict" : false,
      "type" : "json_schema"
    },
    "verbosity" : "medium"
  },
  "tool_choice" : "auto",
  "tools" : [

  ],
  "top_logprobs" : 0,
  "top_p" : 0.97999999999999998,
  "truncation" : "disabled",
  "usage" : {
    "input_tokens" : 76,
    "input_tokens_details" : {
      "cached_tokens" : 0
    },
    "output_tokens" : 23,
    "output_tokens_details" : {
      "reasoning_tokens" : 0
    },
    "total_tokens" : 99
  },
  "user" : null
}
"""#
