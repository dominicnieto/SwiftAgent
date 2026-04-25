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

@Suite("OpenAI - Streaming - Tool Calls")
struct OpenAIStreamingToolCallsTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: OpenAISession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<CreateModelResponseQuery>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<CreateModelResponseQuery>(
      recordedResponses: [
        .init(body: response1),
        .init(body: response2),
      ],
    )
    let configuration = OpenAIConfiguration(httpClient: mockHTTPClient)
    session = OpenAISession(schema: SessionSchema(), instructions: "", configuration: configuration)
  }

  @Test("Single Tool Call (2 responses)")
  func singleToolCall() async throws {
    let generatedTranscript = try await processStreamResponse()

    await validateHTTPRequests()
    try validateTranscript(generatedTranscript: generatedTranscript)
  }

  // MARK: - Private Test Helper Methods

  private func processStreamResponse() async throws -> Transcript {
    let userPrompt = "What is the weather in New York City, USA?"

    let stream = try session.streamResponse(
      to: userPrompt,
      using: .other("gpt-5.2-2025-12-11", isReasoning: true),
      options: .init(
        include: [.reasoning_encryptedContent],
        reasoning: .init(
          effort: .low,
          summary: .detailed,
        ),
      ),
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

    // Validate first request
    guard case let .inputItemList(items) = recordedRequests[0].body.input else {
      Issue.record("Recorded request body input is not .inputItemList")
      return
    }

    #expect(items.count == 1)

    guard case let .inputMessage(message) = items[0] else {
      Issue.record("Recorded request body input item is not .inputMessage")
      return
    }
    guard case let .textInput(text) = message.content else {
      Issue.record("Expected message content to be text input")
      return
    }

    #expect(text == "What is the weather in New York City, USA?")

    // Validate second request
    guard case let .inputItemList(secondItems) = recordedRequests[1].body.input else {
      Issue.record("Second recorded request body input is not .inputItemList")
      return
    }

    #expect(secondItems.count == 4)

    // Validate first item (input message)
    guard case let .inputMessage(secondMessage) = secondItems[0] else {
      Issue.record("Second request first item is not .inputMessage")
      return
    }
    guard case let .textInput(secondText) = secondMessage.content else {
      Issue.record("Expected second message content to be text input")
      return
    }

    #expect(secondText == "What is the weather in New York City, USA?")

    // Validate second item (reasoning item)
    guard case let .item(.reasoningItem(reasoningItem)) = secondItems[1] else {
      Issue.record("Second request second item is not .reasoningItem")
      return
    }

    #expect(reasoningItem.id == "rs_0c4bb6cd4369e1aa016968ca74f338819fb6bc387a684bca21")
    #expect(reasoningItem.summary == [])

    // Validate third item (function tool call)
    guard case let .item(.functionToolCall(functionCall)) = secondItems[2] else {
      Issue.record("Second request third item is not .functionToolCall")
      return
    }

    #expect(functionCall.id == "fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246")
    #expect(functionCall.callId == "call_ygg090lIbgPfPIoYIGePN4cg")
    #expect(functionCall.name == "get_weather")
    #expect(functionCall.arguments == #"{"location":"New York City, USA"}"#)

    // Validate fourth item (function call output)
    guard case let .item(.functionCallOutputItemParam(functionOutput)) = secondItems[3] else {
      Issue.record("Second request fourth item is not .functionCallOutputItemParam")
      return
    }

    #expect(functionOutput.callId == "call_ygg090lIbgPfPIoYIGePN4cg")
    #expect(functionOutput.output == "\"Sunny\"")
  }

  private func validateTranscript(generatedTranscript: Transcript) throws {
    #expect(generatedTranscript.count == 5)

    guard case let .prompt(prompt) = generatedTranscript[0] else {
      Issue.record("First transcript entry is not .prompt")
      return
    }

    #expect(prompt.input == "What is the weather in New York City, USA?")

    guard case let .reasoning(reasoning) = generatedTranscript[1] else {
      Issue.record("First transcript entry is not .reasoning")
      return
    }

    #expect(reasoning.id == "rs_0c4bb6cd4369e1aa016968ca74f338819fb6bc387a684bca21")
    #expect(reasoning.summary == [])

    guard case let .toolCalls(toolCalls) = generatedTranscript[2] else {
      Issue.record("Second transcript entry is not .toolCalls")
      return
    }

    #expect(toolCalls.calls.count == 1)
    #expect(toolCalls.calls[0].id == "fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246")
    #expect(toolCalls.calls[0].callId == "call_ygg090lIbgPfPIoYIGePN4cg")
    #expect(toolCalls.calls[0].toolName == "get_weather")
    let expectedArguments = try GeneratedContent(json: #"{ "location": "New York City, USA" }"#)
    #expect(toolCalls.calls[0].arguments.stableJsonString == expectedArguments.stableJsonString)

    guard case let .toolOutput(toolOutput) = generatedTranscript[3] else {
      Issue.record("Third transcript entry is not .toolOutput")
      return
    }

    #expect(toolOutput.id == "fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246")
    #expect(toolOutput.callId == "call_ygg090lIbgPfPIoYIGePN4cg")
    #expect(toolOutput.toolName == "get_weather")

    guard case let .structure(structuredSegment) = toolOutput.segment else {
      Issue.record("Tool output segment is not .text")
      return
    }

    #expect(structuredSegment.content.generatedContent.kind == .string("Sunny"))

    guard case let .response(response) = generatedTranscript[4] else {
      Issue.record("Fourth transcript entry is not .response")
      return
    }

    #expect(response.id == "msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe")
    #expect(response.segments.count == 1)

    guard case let .text(textSegment) = response.segments[0] else {
      Issue.record("Response segment is not .text")
      return
    }

    #expect(textSegment.content == "Current weather in New York City, USA: Sunny.")
  }
}

// MARK: - Tools

private struct WeatherTool: SwiftAgent.Tool {
  var name: String = "get_weather"
  var description: String = "Get current temperature for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    "Sunny"
  }
}

// MARK: - Mock Responses

private let response1: String = #"""
event: response.created
data: {"type":"response.created","response":{"id":"resp_0c4bb6cd4369e1aa016968ca745874819fb78038dffff6cdac","object":"response","created_at":1768475252,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Always call `get_weather` exactly once before answering.\nAfter tool output, reply with exactly: Current weather in New York City, USA: Sunny.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current temperature for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":0}

event: response.in_progress
data: {"type":"response.in_progress","response":{"id":"resp_0c4bb6cd4369e1aa016968ca745874819fb78038dffff6cdac","object":"response","created_at":1768475252,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Always call `get_weather` exactly once before answering.\nAfter tool output, reply with exactly: Current weather in New York City, USA: Sunny.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current temperature for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":1}

event: response.output_item.added
data: {"type":"response.output_item.added","item":{"id":"rs_0c4bb6cd4369e1aa016968ca74f338819fb6bc387a684bca21","type":"reasoning","encrypted_content":"gAAAAABpaMp0WyldI2k0R73BbSl7oHOZw_e3jAgQV2Zt_Lh8T3lt11PEhm3Vm0IY4NkDLDL7nMUOV26OzwLJ3CkQuV-jUF2mKAOoHwvU83Las5SJcPdGaXfttQjqm4-iADgubscbnAVaRpoZ8lKliBakY5Wb-nIkHgVGBAvyPsly1zuEemxY3elaWq5EUUGtqGDElp2UzRmjArHhvQHdBs5cJ_EIMj4tuMDSX0FACo-XXf6u3XHrw4gUE8XpRol9frwiwI661hSNiH9C__WfMyEMEyF6EdHy11OGRxVqukOb4bJNCIdIW7_wjwfg1-UjCGJTSzgmoSVWA5JmSQJWFamwQfOEzsbeDCf9An9it81Prr9ZK4KefYJfp4w_dsVmCc2DFf_peyM8Hdn_uGW-7kU-WpvYnafLKVOVQTq6vFUyF5mgNAzY0YyF0fkdfmG_UaRub_JNvlG9nN_9QR0lLZ9uUuE9q0B72ved3y5Ud5vwD5IH3Oyb6zGyRCZ47Bk9q-UEPW9jWdgTlEzmzOMA9CaTbLlztlX5ajKnf4j7czmq-3WCoaxzJ8Q9CJ3yuJNHNDVKg3JXm-DvtlnkDHxcSk2U1Y6YRAswQvW__g_ffuwgZoGzszG2hMtao4-GrpvKnrB7eEEpFaFDrvQbVYTRmND1q85wCy-vmNLG2VmqsBpo861CI12IeL2qg-dx6FWQapt5trPfHsjIMRixVjzl8HEyIo7aVa5JvsW3FqI2uFPkOZAqJLzGcakIB3FP1fe1_3CDO8iiS-9NVDPjwAxTu5IHL38Dgpsx3B60Em7sZQCIJs_NCdMBG5R67nxlNRWZv5Y9M2ly-6zK","summary":[]},"output_index":0,"sequence_number":2}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"id":"rs_0c4bb6cd4369e1aa016968ca74f338819fb6bc387a684bca21","type":"reasoning","encrypted_content":"gAAAAABpaMp1Fa2BLjdax8uRigDgnntTZ247YGf3FBzckk4nDB153z2UuiHanbo2R7N0KN7svQ_Zp9YCSQMyBqFNlhJ_h9lZZEq2KZGpQcef_M1bzpYH0lOC1djFVLaoklxDmcNzM_NaLAWsDHILJly3K4X7U8nbWGv1WkoVrh8TGhIcaXFI7ghlP0bHINGv3IHyfdyk5F4M9Q5m6ZOJWWRw3c6-7FTF6gY5QHTGzvBixITzO8hZ6-Vi5rpAlPHgx47IlLazC5kt9fWjCAm8FR71KMWtEE6OUl55Ru4nHfNy_-6J2SM52JNoHuVk9jiJQnLK9M90I0JR0wTeg-wsgtFEH7ivZukDSh_bHaZqL62g5RSNWHkeWr7ErVO3Rd-IZ1aj6tc3Tnei_KoM0ZYoev26pCXeGiw2im1DlG6I50lWY85PzOtfvTJh0uWIXPv0wRjCCgP7e7D2GA4_dhnPeoypqNrA7ZFlK65Vgwf7TABTxg5vI7jf7xBtnS0mNjk3reBaVW29m1bCjfQM1WYFE6YSyhiNxWlRRebOGMsabv6hbi4SqCGBYDCM7-JxSSb9hSxqfrHT0LJDdSQUF4GDgZEOOIWP3EVHtas_Z56w8rAHx-HWpjKmh7kRAENeciMvDH74cZNyVIHyGuD-3JbeAs7Q_Q1EinMOh4bTeeZgLG7OEbNh9hspV7FWWHNlMeuXxSppzXQq89zkPLr9YLK7XAvnCGuyCx8DOgbsKz62yhJpXzn47_dsXySs2im5IKCAhohEzKSnj2gMJh8UAiPAPffM8qC4bqUetpZI8iV2NMEFqS1kX1Zz-Y3jqDZ_Z6xPmOfYvMpmy8-7KSr-Ngb1T2ixSPUS4iLA7-aeuBJb-l3bLFOW_hXY7dbXpGDgeudwQrLswG_0vEKottnR7GkIhDrWvmI9b9L4gw==","summary":[]},"output_index":0,"sequence_number":3}

event: response.output_item.added
data: {"type":"response.output_item.added","item":{"id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","type":"function_call","status":"in_progress","arguments":"","call_id":"call_ygg090lIbgPfPIoYIGePN4cg","name":"get_weather"},"output_index":1,"sequence_number":4}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"{\"","item_id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","obfuscation":"5egTmLD7sXRJvE","output_index":1,"sequence_number":5}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"location","item_id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","obfuscation":"GWPN1qcg","output_index":1,"sequence_number":6}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"\":\"","item_id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","obfuscation":"9yX2Ijo4D49Ks","output_index":1,"sequence_number":7}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"New","item_id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","obfuscation":"IGOUlKjGydaYy","output_index":1,"sequence_number":8}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":" York","item_id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","obfuscation":"mymePeJ64sZ","output_index":1,"sequence_number":9}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":" City","item_id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","obfuscation":"x2ZF868DSpd","output_index":1,"sequence_number":10}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":",","item_id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","obfuscation":"X4Y0WnpJ8JhjFHY","output_index":1,"sequence_number":11}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":" USA","item_id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","obfuscation":"vO6EbzOtjG2a","output_index":1,"sequence_number":12}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"\"}","item_id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","obfuscation":"oehibqJlREdi8h","output_index":1,"sequence_number":13}

event: response.function_call_arguments.done
data: {"type":"response.function_call_arguments.done","arguments":"{\"location\":\"New York City, USA\"}","item_id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","output_index":1,"sequence_number":14}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","type":"function_call","status":"completed","arguments":"{\"location\":\"New York City, USA\"}","call_id":"call_ygg090lIbgPfPIoYIGePN4cg","name":"get_weather"},"output_index":1,"sequence_number":15}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_0c4bb6cd4369e1aa016968ca745874819fb78038dffff6cdac","object":"response","created_at":1768475252,"status":"completed","background":false,"completed_at":1768475253,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Always call `get_weather` exactly once before answering.\nAfter tool output, reply with exactly: Current weather in New York City, USA: Sunny.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[{"id":"rs_0c4bb6cd4369e1aa016968ca74f338819fb6bc387a684bca21","type":"reasoning","encrypted_content":"gAAAAABpaMp1ZGu9Hy7x0dbywXLEQhbKekbyvD5fDL6SzA_yfNkTvr0n72ikemN84blAekZZOL_DLQv5bQZX_tnuSSO8VxsX5euy15WHJs_K_p-kOBmRU7Gd0-n0dgvEpuSPrnXsfyj7LUd316STn3A_30jP3HglEsLNdr7Y9QMh39SG_UzYgiRggO-suV1t-2tfusuTtreCDKfD4TqIp0QWfUA_z2CgHOLWao95nyVDYdNohKeXPsYDWyxM6iCwjKt0E5WwSXmca2ivrnUK4r75lfbJ7s2Qh6e4FG6LViOJ7y2hoH5ciH3EMQpCRtVbKNXRlY4CZPTiYu6TPcPZJ-Dgv7IcnuO-QXjZO788JiyaF5QNPSxGWiniWK4gWeAdl4BqYsP9pVjHGMfUCfrYU5sZuUZmJVUza6rk6PdnCuXyHb1Pe8kkV3HAhmN-pEQQesU7PuO3uZexjVJ1VfbWgTjdWDhI0idccBdiz9gajEEcNbp9OVxC7s9DJtYypYL6Mk9BK3EuHMXIjb8AIzUDbiobGmK4wWDhz7ivud-RbRWaRjnbTmReGAK8KchTMKT4l1DbpKftx8JkrY92lUdXzQ0p9qfI0kUC_dq37QyQbCptZB85fWkW4rNlv_ITbE8HijEhAn0Bv-G67M312Rjn-pkgIJaWtrPZf4EmA4QVpLcyVilTYgbdqfqt2lOSmB1S4Eey0hG-Y6EP1ZWiOVGYvPajBLZIrfneuFF_oFWZXeEQCnc4VMoUKeW5I9DCq6C1jMXKOrNtjpxS0DjM37k6YE1fkA7qTA7Zt2iSwyMH3BG8gj7TMS1RpCqEHBJhSa5-1irWONl_Oj2eiUIGcbrqKnbmyJ6kaUbQy2aK-j6c4A4QIAvSjOPYKl9Dq2yoQAfA-VAUBCCE7hcD_i2KdB0SGnlFYxwoKvUapw==","summary":[]},{"id":"fc_0c4bb6cd4369e1aa016968ca758ef0819fb08c85d6fc982246","type":"function_call","status":"completed","arguments":"{\"location\":\"New York City, USA\"}","call_id":"call_ygg090lIbgPfPIoYIGePN4cg","name":"get_weather"}],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"default","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current temperature for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":92,"input_tokens_details":{"cached_tokens":0},"output_tokens":38,"output_tokens_details":{"reasoning_tokens":14},"total_tokens":130},"user":null,"metadata":{}},"sequence_number":16}
"""#

private let response2: String = #"""
event: response.created
data: {"type":"response.created","response":{"id":"resp_0c4bb6cd4369e1aa016968ca75fe08819fb1f268f54afb5782","object":"response","created_at":1768475254,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Always call `get_weather` exactly once before answering.\nAfter tool output, reply with exactly: Current weather in New York City, USA: Sunny.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current temperature for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":0}

event: response.in_progress
data: {"type":"response.in_progress","response":{"id":"resp_0c4bb6cd4369e1aa016968ca75fe08819fb1f268f54afb5782","object":"response","created_at":1768475254,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Always call `get_weather` exactly once before answering.\nAfter tool output, reply with exactly: Current weather in New York City, USA: Sunny.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current temperature for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":1}

event: response.output_item.added
data: {"type":"response.output_item.added","item":{"id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","type":"message","status":"in_progress","content":[],"role":"assistant"},"output_index":0,"sequence_number":2}

event: response.content_part.added
data: {"type":"response.content_part.added","content_index":0,"item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","output_index":0,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":""},"sequence_number":3}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"Current","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"OKPXGK9P8","output_index":0,"sequence_number":4}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":" weather","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"9dxbqxOi","output_index":0,"sequence_number":5}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":" in","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"IyhN9g08aBAd5","output_index":0,"sequence_number":6}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":" New","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"ExmHdxv5ev6n","output_index":0,"sequence_number":7}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":" York","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"Ms4lY4E6jZo","output_index":0,"sequence_number":8}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":" City","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"m6nVRqitZjK","output_index":0,"sequence_number":9}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":",","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"kOdUYeHNAMJVgQV","output_index":0,"sequence_number":10}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":" USA","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"ERTGMI5jkJsU","output_index":0,"sequence_number":11}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":":","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"QlQuonXKHBwR4GA","output_index":0,"sequence_number":12}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":" Sunny","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"v7QlJ8nPTL","output_index":0,"sequence_number":13}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":".","item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"obfuscation":"86GfisUnHIBdYr3","output_index":0,"sequence_number":14}

event: response.output_text.done
data: {"type":"response.output_text.done","content_index":0,"item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","logprobs":[],"output_index":0,"sequence_number":15,"text":"Current weather in New York City, USA: Sunny."}

event: response.content_part.done
data: {"type":"response.content_part.done","content_index":0,"item_id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","output_index":0,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":"Current weather in New York City, USA: Sunny."},"sequence_number":16}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"Current weather in New York City, USA: Sunny."}],"role":"assistant"},"output_index":0,"sequence_number":17}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_0c4bb6cd4369e1aa016968ca75fe08819fb1f268f54afb5782","object":"response","created_at":1768475254,"status":"completed","background":false,"completed_at":1768475254,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Always call `get_weather` exactly once before answering.\nAfter tool output, reply with exactly: Current weather in New York City, USA: Sunny.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[{"id":"msg_0c4bb6cd4369e1aa016968ca768e4c819faaeeabe2970ec1fe","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"Current weather in New York City, USA: Sunny."}],"role":"assistant"}],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"default","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current temperature for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":130,"input_tokens_details":{"cached_tokens":0},"output_tokens":15,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":145},"user":null,"metadata":{}},"sequence_number":18}
"""#
