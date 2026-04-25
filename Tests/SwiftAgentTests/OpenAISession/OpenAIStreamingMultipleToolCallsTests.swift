// By Dennis Müller

import Foundation
import OpenAI
@testable import OpenAISession
@testable import SwiftAgent
import Testing

@SessionSchema
private struct SessionSchema {
  @Tool var weather = WeatherTool()
  @Tool var time = TimeTool()
}

@Suite("OpenAI - Streaming - Tool Calls (Multiple)")
struct OpenAIStreamingMultipleToolCallsTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: OpenAISession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<CreateModelResponseQuery>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<CreateModelResponseQuery>(
      recordedResponses: [
        .init(body: toolCallsResponse),
        .init(body: finalResponse),
      ],
    )

    let configuration = OpenAIConfiguration(httpClient: mockHTTPClient)
    session = OpenAISession(
      schema: SessionSchema(),
      instructions: """
      Do not answer with any text before tool calls.
      Call `get_weather` with { "location": "Tokyo" } and `get_time` with { "location": "Tokyo" } in parallel.
      After tool outputs, reply with exactly: Done.
      """,
      configuration: configuration,
    )
  }

  @Test("Two tool calls are executed and both outputs are sent on the second request")
  func twoToolCallsExecuteAndAreForwarded() async throws {
    let (generatedTranscript, latestContent, latestUsage) = try await processStreamResponse()

    await validateHTTPRequests()
    try validateTranscript(generatedTranscript)
    #expect(latestContent == "Done.")
    #expect(latestUsage?.totalTokens == 289)
  }

  // MARK: - Private

  private func processStreamResponse() async throws -> (Transcript, String?, TokenUsage?) {
    let stream = try session.streamResponse(
      to: "Need weather and time.",
      using: .gpt4o,
      options: .init(
        allowParallelToolCalls: true,
        minimumStreamingSnapshotInterval: .zero,
      ),
    )

    var generatedTranscript = Transcript()
    var latestContent: String?
    var latestUsage: TokenUsage?

    for try await snapshot in stream {
      generatedTranscript = snapshot.transcript
      latestUsage = snapshot.tokenUsage

      if let content = snapshot.content {
        latestContent = content
      }
    }

    return (generatedTranscript, latestContent, latestUsage)
  }

  private func validateHTTPRequests() async {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 2)

    guard case let .inputItemList(firstItems) = recordedRequests[0].body.input else {
      Issue.record("First request body input is not .inputItemList")
      return
    }

    #expect(firstItems.count == 1)

    guard case let .inputMessage(firstMessage) = firstItems[0] else {
      Issue.record("First request item is not .inputMessage")
      return
    }
    guard case let .textInput(firstText) = firstMessage.content else {
      Issue.record("Expected first request message content to be .textInput")
      return
    }

    #expect(firstText == "Need weather and time.")

    guard case let .inputItemList(secondItems) = recordedRequests[1].body.input else {
      Issue.record("Second request body input is not .inputItemList")
      return
    }

    #expect(secondItems.count == 5)

    guard case let .inputMessage(secondMessage) = secondItems[0] else {
      Issue.record("Second request first item is not .inputMessage")
      return
    }
    guard case let .textInput(secondText) = secondMessage.content else {
      Issue.record("Expected second request message content to be .textInput")
      return
    }

    #expect(secondText == "Need weather and time.")

    guard case let .item(.functionToolCall(weatherCall)) = secondItems[1] else {
      Issue.record("Second request second item is not .functionToolCall")
      return
    }

    #expect(weatherCall.id == "fc_081fdebf823cdd48016968da328b4c8196911df45eaf948901")
    #expect(weatherCall.callId == "call_GrjS73SHOWUXADDavNRVxvbo")
    #expect(weatherCall.name == "get_weather")
    #expect(weatherCall.arguments == #"{"location":"Tokyo"}"#)

    guard case let .item(.functionToolCall(timeCall)) = secondItems[2] else {
      Issue.record("Second request third item is not .functionToolCall")
      return
    }

    #expect(timeCall.id == "fc_081fdebf823cdd48016968da32a0c08196bd608e34e9c921da")
    #expect(timeCall.callId == "call_5tGgorox68dMuXHYnC5ttcuY")
    #expect(timeCall.name == "get_time")
    #expect(timeCall.arguments == #"{"location":"Tokyo"}"#)

    guard case let .item(.functionCallOutputItemParam(weatherOutput)) = secondItems[3] else {
      Issue.record("Second request fourth item is not .functionCallOutputItemParam")
      return
    }

    #expect(weatherOutput.callId == "call_GrjS73SHOWUXADDavNRVxvbo")
    #expect(weatherOutput.output == "\"Sunny\"")

    guard case let .item(.functionCallOutputItemParam(timeOutput)) = secondItems[4] else {
      Issue.record("Second request fifth item is not .functionCallOutputItemParam")
      return
    }

    #expect(timeOutput.callId == "call_5tGgorox68dMuXHYnC5ttcuY")
    #expect(timeOutput.output == "\"12:34\"")
  }

  private func validateTranscript(
    _ transcript: Transcript,
  ) throws {
    #expect(transcript.count == 6)

    guard case let .prompt(promptEntry) = transcript[0] else {
      Issue.record("Expected first transcript entry to be .prompt")
      return
    }

    #expect(promptEntry.input == "Need weather and time.")

    guard case let .toolCalls(weatherToolCalls) = transcript[1] else {
      Issue.record("Expected second transcript entry to be .toolCalls")
      return
    }

    #expect(weatherToolCalls.calls.count == 1)
    #expect(weatherToolCalls.calls[0].toolName == "get_weather")

    guard case let .toolCalls(timeToolCalls) = transcript[2] else {
      Issue.record("Expected third transcript entry to be .toolCalls")
      return
    }

    #expect(timeToolCalls.calls.count == 1)
    #expect(timeToolCalls.calls[0].toolName == "get_time")

    guard case let .toolOutput(weatherToolOutput) = transcript[3] else {
      Issue.record("Expected fourth transcript entry to be .toolOutput")
      return
    }

    #expect(weatherToolOutput.toolName == "get_weather")
    guard case let .structure(weatherSegment) = weatherToolOutput.segment else {
      Issue.record("Expected weather tool output segment to be .structure")
      return
    }

    #expect(weatherSegment.content.generatedContent.kind == .string("Sunny"))

    guard case let .toolOutput(timeToolOutput) = transcript[4] else {
      Issue.record("Expected fifth transcript entry to be .toolOutput")
      return
    }

    #expect(timeToolOutput.toolName == "get_time")
    guard case let .structure(timeSegment) = timeToolOutput.segment else {
      Issue.record("Expected time tool output segment to be .structure")
      return
    }

    #expect(timeSegment.content.generatedContent.kind == .string("12:34"))

    guard case let .response(responseEntry) = transcript[5] else {
      Issue.record("Expected sixth transcript entry to be .response")
      return
    }

    #expect(responseEntry.text == "Done.")
  }
}

// MARK: - Tools

private struct WeatherTool: SwiftAgent.Tool {
  var name: String = "get_weather"
  var description: String = "Get current weather for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}

private struct TimeTool: SwiftAgent.Tool {
  var name: String = "get_time"
  var description: String = "Get the current local time for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "12:34"
  }
}

// MARK: - Fixtures

private let toolCallsResponse: String = #"""
event: response.created
data: {"type":"response.created","response":{"id":"resp_081fdebf823cdd48016968da317f8881969df12d2806f0c0d3","object":"response","created_at":1768479281,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Do not answer with any text before tool calls.\nCall `get_weather` with { \"location\": \"Tokyo\" } and `get_time` with { \"location\": \"Tokyo\" } in parallel.\nAfter tool outputs, reply with exactly: Done.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-4o-2024-08-06","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":null,"summary":null},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current weather for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false},{"type":"function","description":"Get the current local time for a given location.","name":"get_time","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":1.0,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":0}

event: response.in_progress
data: {"type":"response.in_progress","response":{"id":"resp_081fdebf823cdd48016968da317f8881969df12d2806f0c0d3","object":"response","created_at":1768479281,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Do not answer with any text before tool calls.\nCall `get_weather` with { \"location\": \"Tokyo\" } and `get_time` with { \"location\": \"Tokyo\" } in parallel.\nAfter tool outputs, reply with exactly: Done.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-4o-2024-08-06","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":null,"summary":null},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current weather for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false},{"type":"function","description":"Get the current local time for a given location.","name":"get_time","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":1.0,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":1}

event: response.output_item.added
data: {"type":"response.output_item.added","item":{"id":"fc_081fdebf823cdd48016968da328b4c8196911df45eaf948901","type":"function_call","status":"in_progress","arguments":"","call_id":"call_GrjS73SHOWUXADDavNRVxvbo","name":"get_weather"},"output_index":0,"sequence_number":2}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"{","item_id":"fc_081fdebf823cdd48016968da328b4c8196911df45eaf948901","obfuscation":"HEsTvGzVLk69x9N","output_index":0,"sequence_number":3}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"\"location","item_id":"fc_081fdebf823cdd48016968da328b4c8196911df45eaf948901","obfuscation":"qfRQKQk","output_index":0,"sequence_number":4}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"\":","item_id":"fc_081fdebf823cdd48016968da328b4c8196911df45eaf948901","obfuscation":"sdnrR9hKDnCsYo","output_index":0,"sequence_number":5}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"\"Tokyo","item_id":"fc_081fdebf823cdd48016968da328b4c8196911df45eaf948901","obfuscation":"h2CMKORKXx","output_index":0,"sequence_number":6}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"\"}","item_id":"fc_081fdebf823cdd48016968da328b4c8196911df45eaf948901","obfuscation":"kpIjrCEjAyN55U","output_index":0,"sequence_number":7}

event: response.function_call_arguments.done
data: {"type":"response.function_call_arguments.done","arguments":"{\"location\":\"Tokyo\"}","item_id":"fc_081fdebf823cdd48016968da328b4c8196911df45eaf948901","output_index":0,"sequence_number":8}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"id":"fc_081fdebf823cdd48016968da328b4c8196911df45eaf948901","type":"function_call","status":"completed","arguments":"{\"location\":\"Tokyo\"}","call_id":"call_GrjS73SHOWUXADDavNRVxvbo","name":"get_weather"},"output_index":0,"sequence_number":9}

event: response.output_item.added
data: {"type":"response.output_item.added","item":{"id":"fc_081fdebf823cdd48016968da32a0c08196bd608e34e9c921da","type":"function_call","status":"in_progress","arguments":"","call_id":"call_5tGgorox68dMuXHYnC5ttcuY","name":"get_time"},"output_index":1,"sequence_number":10}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"{","item_id":"fc_081fdebf823cdd48016968da32a0c08196bd608e34e9c921da","obfuscation":"IkjZ26ZCWE4tXmv","output_index":1,"sequence_number":11}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"\"location","item_id":"fc_081fdebf823cdd48016968da32a0c08196bd608e34e9c921da","obfuscation":"opvt1eR","output_index":1,"sequence_number":12}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"\":","item_id":"fc_081fdebf823cdd48016968da32a0c08196bd608e34e9c921da","obfuscation":"HrFA5QWmldNDrn","output_index":1,"sequence_number":13}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"\"Tokyo","item_id":"fc_081fdebf823cdd48016968da32a0c08196bd608e34e9c921da","obfuscation":"AEHkT2jmlh","output_index":1,"sequence_number":14}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","delta":"\"}","item_id":"fc_081fdebf823cdd48016968da32a0c08196bd608e34e9c921da","obfuscation":"Vj9agP40QYAoAf","output_index":1,"sequence_number":15}

event: response.function_call_arguments.done
data: {"type":"response.function_call_arguments.done","arguments":"{\"location\":\"Tokyo\"}","item_id":"fc_081fdebf823cdd48016968da32a0c08196bd608e34e9c921da","output_index":1,"sequence_number":16}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"id":"fc_081fdebf823cdd48016968da32a0c08196bd608e34e9c921da","type":"function_call","status":"completed","arguments":"{\"location\":\"Tokyo\"}","call_id":"call_5tGgorox68dMuXHYnC5ttcuY","name":"get_time"},"output_index":1,"sequence_number":17}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_081fdebf823cdd48016968da317f8881969df12d2806f0c0d3","object":"response","created_at":1768479281,"status":"completed","background":false,"completed_at":1768479282,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Do not answer with any text before tool calls.\nCall `get_weather` with { \"location\": \"Tokyo\" } and `get_time` with { \"location\": \"Tokyo\" } in parallel.\nAfter tool outputs, reply with exactly: Done.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-4o-2024-08-06","output":[{"id":"fc_081fdebf823cdd48016968da328b4c8196911df45eaf948901","type":"function_call","status":"completed","arguments":"{\"location\":\"Tokyo\"}","call_id":"call_GrjS73SHOWUXADDavNRVxvbo","name":"get_weather"},{"id":"fc_081fdebf823cdd48016968da32a0c08196bd608e34e9c921da","type":"function_call","status":"completed","arguments":"{\"location\":\"Tokyo\"}","call_id":"call_5tGgorox68dMuXHYnC5ttcuY","name":"get_time"}],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":null,"summary":null},"safety_identifier":null,"service_tier":"default","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current weather for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false},{"type":"function","description":"Get the current local time for a given location.","name":"get_time","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":1.0,"truncation":"disabled","usage":{"input_tokens":64,"input_tokens_details":{"cached_tokens":0},"output_tokens":44,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":108},"user":null,"metadata":{}},"sequence_number":18}
"""#

private let finalResponse: String = #"""
event: response.created
data: {"type":"response.created","response":{"id":"resp_081fdebf823cdd48016968da3378688196bb74cfd57f278ffa","object":"response","created_at":1768479283,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Do not answer with any text before tool calls.\nCall `get_weather` with { \"location\": \"Tokyo\" } and `get_time` with { \"location\": \"Tokyo\" } in parallel.\nAfter tool outputs, reply with exactly: Done.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-4o-2024-08-06","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":null,"summary":null},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current weather for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false},{"type":"function","description":"Get the current local time for a given location.","name":"get_time","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":1.0,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":0}

event: response.in_progress
data: {"type":"response.in_progress","response":{"id":"resp_081fdebf823cdd48016968da3378688196bb74cfd57f278ffa","object":"response","created_at":1768479283,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Do not answer with any text before tool calls.\nCall `get_weather` with { \"location\": \"Tokyo\" } and `get_time` with { \"location\": \"Tokyo\" } in parallel.\nAfter tool outputs, reply with exactly: Done.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-4o-2024-08-06","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":null,"summary":null},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current weather for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false},{"type":"function","description":"Get the current local time for a given location.","name":"get_time","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":1.0,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":1}

event: response.output_item.added
data: {"type":"response.output_item.added","item":{"id":"msg_081fdebf823cdd48016968da346a1c8196a08061003725460e","type":"message","status":"in_progress","content":[],"role":"assistant"},"output_index":0,"sequence_number":2}

event: response.content_part.added
data: {"type":"response.content_part.added","content_index":0,"item_id":"msg_081fdebf823cdd48016968da346a1c8196a08061003725460e","output_index":0,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":""},"sequence_number":3}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"Done","item_id":"msg_081fdebf823cdd48016968da346a1c8196a08061003725460e","logprobs":[],"obfuscation":"qegfn9JrxJA9","output_index":0,"sequence_number":4}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":".","item_id":"msg_081fdebf823cdd48016968da346a1c8196a08061003725460e","logprobs":[],"obfuscation":"DMTMOXIar20CxGO","output_index":0,"sequence_number":5}

event: response.output_text.done
data: {"type":"response.output_text.done","content_index":0,"item_id":"msg_081fdebf823cdd48016968da346a1c8196a08061003725460e","logprobs":[],"output_index":0,"sequence_number":6,"text":"Done."}

event: response.content_part.done
data: {"type":"response.content_part.done","content_index":0,"item_id":"msg_081fdebf823cdd48016968da346a1c8196a08061003725460e","output_index":0,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":"Done."},"sequence_number":7}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"id":"msg_081fdebf823cdd48016968da346a1c8196a08061003725460e","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"Done."}],"role":"assistant"},"output_index":0,"sequence_number":8}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_081fdebf823cdd48016968da3378688196bb74cfd57f278ffa","object":"response","created_at":1768479283,"status":"completed","background":false,"completed_at":1768479284,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Do not answer with any text before tool calls.\nCall `get_weather` with { \"location\": \"Tokyo\" } and `get_time` with { \"location\": \"Tokyo\" } in parallel.\nAfter tool outputs, reply with exactly: Done.","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-4o-2024-08-06","output":[{"id":"msg_081fdebf823cdd48016968da346a1c8196a08061003725460e","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"Done."}],"role":"assistant"}],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":null,"summary":null},"safety_identifier":null,"service_tier":"default","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"Get current weather for a given location.","name":"get_weather","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false},{"type":"function","description":"Get the current local time for a given location.","name":"get_time","parameters":{"additionalProperties":false,"properties":{"location":{"type":"string"}},"required":["location"],"title":"Arguments","type":"object","x-order":["location"]},"strict":false}],"top_logprobs":0,"top_p":1.0,"truncation":"disabled","usage":{"input_tokens":177,"input_tokens_details":{"cached_tokens":0},"output_tokens":4,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":181},"user":null,"metadata":{}},"sequence_number":9}
"""#
