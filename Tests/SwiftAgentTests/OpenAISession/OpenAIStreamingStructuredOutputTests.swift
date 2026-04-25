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

@Suite("OpenAI - Streaming - Structured Output")
struct OpenAIStreamingStructuredOutputTests {
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

  @Test("Single response")
  func singleResponse() async throws {
    try await processStreamResponse()
    try await validateRecordedHTTPRequests()
  }

  private func processStreamResponse() async throws {
    let stream = try session.streamResponse(
      to: "Provide the latest weather update.",
      generating: \.weatherForecast,
      using: .other("gpt-5.2-2025-12-11", isReasoning: true),
      options: .init(
        include: [.reasoning_encryptedContent],
        reasoning: .init(
          effort: .low,
          summary: .detailed,
        ),
        minimumStreamingSnapshotInterval: .zero,
      ),
    )

    var generatedTranscript = Transcript()
    var generatedOutputSnapshots: [WeatherForecast.Schema.PartiallyGenerated] = []

    for try await snapshot in stream {
      generatedTranscript = snapshot.transcript

      if let content = snapshot.content {
        generatedOutputSnapshots.append(content)
      }
    }

    validateAgentResponse(generatedTranscript: generatedTranscript)
    validateGeneratedOutput(generatedOutputs: generatedOutputSnapshots)
  }

  private func validateRecordedHTTPRequests() async throws {
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

  private func validateGeneratedOutput(generatedOutputs: [WeatherForecast.Schema.PartiallyGenerated]) {
    #expect(generatedOutputs.isEmpty == false)

    let first = generatedOutputs.first
    #expect(first?.temperatureCelsius == nil)
    #expect(first?.condition == nil)

    #expect(generatedOutputs.contains(where: { $0.temperatureCelsius == 22.0 }))
    #expect(generatedOutputs.contains(where: { $0.condition == "Part" }))
    #expect(generatedOutputs.contains(where: { $0.condition == "Partly" }))
    #expect(generatedOutputs.contains(where: { $0.condition == "Partly Cloud" }))

    let last = generatedOutputs.last
    #expect(last?.temperatureCelsius == 22.0)
    #expect(last?.condition == "Partly Cloudy")
  }

  private func validateAgentResponse(generatedTranscript: Transcript) {
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
event: response.created
data: {"type":"response.created","response":{"id":"resp_099b1acf00be9156016968ca7336248194b0ee603e010cde66","object":"response","created_at":1768475251,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Return temperatureCelsius=22 and condition=Partly Cloudy.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"json_schema","description":null,"name":"weather_forecast","schema":{"additionalProperties":false,"properties":{"condition":{"type":"string"},"temperatureCelsius":{"type":"number"}},"required":["temperatureCelsius","condition"],"title":"Schema","type":"object","x-order":["temperatureCelsius","condition"]},"strict":false},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":0}

event: response.in_progress
data: {"type":"response.in_progress","response":{"id":"resp_099b1acf00be9156016968ca7336248194b0ee603e010cde66","object":"response","created_at":1768475251,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Return temperatureCelsius=22 and condition=Partly Cloudy.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"json_schema","description":null,"name":"weather_forecast","schema":{"additionalProperties":false,"properties":{"condition":{"type":"string"},"temperatureCelsius":{"type":"number"}},"required":["temperatureCelsius","condition"],"title":"Schema","type":"object","x-order":["temperatureCelsius","condition"]},"strict":false},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":1}

event: response.output_item.added
data: {"type":"response.output_item.added","item":{"id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","type":"message","status":"in_progress","content":[],"role":"assistant"},"output_index":0,"sequence_number":2}

event: response.content_part.added
data: {"type":"response.content_part.added","content_index":0,"item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","output_index":0,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":""},"sequence_number":3}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"{\"","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"KZu1MDybNUnQRm","output_index":0,"sequence_number":4}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"temperature","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"7EzRp","output_index":0,"sequence_number":5}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"C","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"oJGQiZvvhHsBGae","output_index":0,"sequence_number":6}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"elsius","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"3AJNVPQqge","output_index":0,"sequence_number":7}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"\":","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"qhkQ7DobSiLYJz","output_index":0,"sequence_number":8}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"22","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"8lGgPFXZRYaogP","output_index":0,"sequence_number":9}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":",\"","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"ko9HPgz6Mnwuxo","output_index":0,"sequence_number":10}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"condition","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"UukT5LJ","output_index":0,"sequence_number":11}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"\":\"","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"Yi10eyxBXBESa","output_index":0,"sequence_number":12}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"Part","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"H78uEw57upVf","output_index":0,"sequence_number":13}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"ly","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"I06XL14CouAwng","output_index":0,"sequence_number":14}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":" Cloud","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"I7WKJ2xHIz","output_index":0,"sequence_number":15}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"y","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"v2tzwqTqLvRr8H5","output_index":0,"sequence_number":16}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"\"}","item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"obfuscation":"idkL4d1UFQK5RK","output_index":0,"sequence_number":17}

event: response.output_text.done
data: {"type":"response.output_text.done","content_index":0,"item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","logprobs":[],"output_index":0,"sequence_number":18,"text":"{\"temperatureCelsius\":22,\"condition\":\"Partly Cloudy\"}"}

event: response.content_part.done
data: {"type":"response.content_part.done","content_index":0,"item_id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","output_index":0,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":"{\"temperatureCelsius\":22,\"condition\":\"Partly Cloudy\"}"},"sequence_number":19}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"{\"temperatureCelsius\":22,\"condition\":\"Partly Cloudy\"}"}],"role":"assistant"},"output_index":0,"sequence_number":20}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_099b1acf00be9156016968ca7336248194b0ee603e010cde66","object":"response","created_at":1768475251,"status":"completed","background":false,"completed_at":1768475252,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Return temperatureCelsius=22 and condition=Partly Cloudy.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[{"id":"msg_099b1acf00be9156016968ca73df008194b199ca91abb57c9f","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"{\"temperatureCelsius\":22,\"condition\":\"Partly Cloudy\"}"}],"role":"assistant"}],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"default","store":false,"temperature":1.0,"text":{"format":{"type":"json_schema","description":null,"name":"weather_forecast","schema":{"additionalProperties":false,"properties":{"condition":{"type":"string"},"temperatureCelsius":{"type":"number"}},"required":["temperatureCelsius","condition"],"title":"Schema","type":"object","x-order":["temperatureCelsius","condition"]},"strict":false},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":76,"input_tokens_details":{"cached_tokens":0},"output_tokens":23,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":99},"user":null,"metadata":{}},"sequence_number":21}
"""#
