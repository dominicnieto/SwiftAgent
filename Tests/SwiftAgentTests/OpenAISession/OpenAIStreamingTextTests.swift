// By Dennis Müller

import Foundation
import OpenAI
@testable import OpenAISession
@testable import SwiftAgent
import Testing

@SessionSchema
private struct SessionSchema {}

@Suite("OpenAI - Streaming - Text")
struct OpenAIStreamingTextTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: OpenAISession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<CreateModelResponseQuery>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<CreateModelResponseQuery>(
      recordedResponse: .init(body: helloWorldResponse),
    )
    let configuration = OpenAIConfiguration(httpClient: mockHTTPClient)
    session = OpenAISession(schema: SessionSchema(), instructions: "", configuration: configuration)
  }

  @Test("Single response")
  func singleResponse() async throws {
    let (generatedTranscript, latestContent) = try await processStreamResponse()
    await validateHTTPRequests()
    try validateTranscript(generatedTranscript: generatedTranscript)
    #expect(latestContent == "Hello, World!")
  }

  // MARK: - Private Test Helper Methods

  private func processStreamResponse() async throws -> (Transcript, String?) {
    let stream = try session.streamResponse(
      to: "prompt",
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

    guard case let .inputItemList(items) = recordedRequests[0].body.input else {
      Issue.record("Recorded request body input is not .inputItemList")
      return
    }

    #expect(items.count == 1)

    guard case let .inputMessage(message)? = items.first else {
      Issue.record("Recorded request body input item is not .inputMessage")
      return
    }
    guard case let .textInput(text) = message.content else {
      Issue.record("Expected message content to be text input")
      return
    }

    #expect(text == "prompt")
  }

  private func validateTranscript(generatedTranscript: Transcript) throws {
    #expect(generatedTranscript.count == 3)

    guard case let .prompt(prompt) = generatedTranscript[0] else {
      Issue.record("First transcript entry is not .prompt")
      return
    }

    #expect(prompt.input == "prompt")

    guard case let .reasoning(reasoning) = generatedTranscript[1] else {
      Issue.record("First transcript entry is not .reasoning")
      return
    }

    #expect(reasoning.id == "rs_04e21c25f1df9e70016968ca71ce0c819da13ed36ddaf37baa")
    #expect(reasoning.summary == [])

    guard case let .response(response) = generatedTranscript[2] else {
      Issue.record("Second transcript entry is not .response")
      return
    }

    #expect(response.id == "msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb")
    #expect(response.segments.count == 1)
    guard case let .text(textSegment) = response.segments.first else {
      Issue.record("Second transcript entry is not .text")
      return
    }

    #expect(textSegment.content == "Hello, World!")
  }
}

// MARK: - Mock Responses

private let helloWorldResponse: String = #"""
event: response.created
data: {"type":"response.created","response":{"id":"resp_04e21c25f1df9e70016968ca712e60819d94c98ca6e7d90576","object":"response","created_at":1768475249,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Reply with exactly: Hello, World!","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":0}

event: response.in_progress
data: {"type":"response.in_progress","response":{"id":"resp_04e21c25f1df9e70016968ca712e60819d94c98ca6e7d90576","object":"response","created_at":1768475249,"status":"in_progress","background":false,"completed_at":null,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Reply with exactly: Hello, World!","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"auto","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":null,"user":null,"metadata":{}},"sequence_number":1}

event: response.output_item.added
data: {"type":"response.output_item.added","item":{"id":"rs_04e21c25f1df9e70016968ca71ce0c819da13ed36ddaf37baa","type":"reasoning","encrypted_content":"gAAAAABpaMpxhz3-6CUVEuH4W-dzd4fRUCiezVBalL3iRZGjnJNbiyRksf0Pg5AgHhKkb1rQPYVcbsQGDcFVbeVg8agm9VzvGmkFEwidBMvXlVmghyWFupH4aJPUllFdtNRBVYRr3hF5UVvFI1uf1L4_LYlw_IpqYtTg0d0M9URqkHxs_2flF3fe_iSfd1S5aEjOYeBWVQr7YRc9TOQGqZlwwlFB3Yr3lo8S_KFds5fFgiGR5oMUEBTVSMj9eQiE3aK9qQnb1kuNdhDk3w1qmXEJ3sB_rkXQnT6zy1AKHHxrizXvy8aE3Mz2uPLZ12g1_Ar3jpaqukwzFVM4D2-UR9SeV778ZF9H1mqCzwiBD_z80CPdCt7u6elTwApj61SZvJGw42FiaagZ1oDoAIHFGcmv_QJYLyNsVkwqshN7S0bJclqAfa0rr42MaWZqjq0MWuipVhvWOe30oG-wgU5zdDfIBpVpVrdnrJGkmYrKCLouWHxO5y_u3YhUGtK-eF0wq5uAXZhK5A0yIZx5VN3qOQyAZ1IDgcyYOMMzeV3Zb_4Lvwsctjm7CtbvKPuD43vLAdMZBsllQtdsR8Q_Lo4lkcekmD8dZlI0bDhl677GCwT_RoieBKsZYesa3lTueSuFKwC0EOxE8PiRfU5GRaLTnjKgCrvlQspdYMZ4p53flxvbKIJarNhGmt3vajTSC33rr4WsmXTo-qeD3wc3EkLH55VodgM1ZtcS_cFsK1d9MKYxsiiSSgdHMIH7jO-fr5w_tkbMYf6hYSs_7yCj3H7GrZszx0ekXYhI7slMFrpag7K4CdYhrvodAy2pWRmIwDr8ntJxHF7Ii6sx","summary":[]},"output_index":0,"sequence_number":2}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"id":"rs_04e21c25f1df9e70016968ca71ce0c819da13ed36ddaf37baa","type":"reasoning","encrypted_content":"gAAAAABpaMpyOC4w4OZJYkRL2mDxb91Q29ue4d-kRET569wBNmXDJK7iiMZhciYCDC8U72ATuOQ4CjM8SxVsoPaFAOw8Fhnwv4s5wKfIqUS_aQwmZkcW6GMnpBeo89AsltxNcpbmECI5CDr53t-hhNf4lVCKzZGYl4GaO-NM4RUoOuR8nK0lwld2pRBopahQ9f3ZmfBz-t4aIanStYb_C7xTFeoMsBKrUKbXBQbSozdQlG1L87yntQGIZR79Xywbi7bL3O1KUmREhh6ZBW7W3N1CsYBJHRfgn0HEyoEwPEbg4SP1xAU-8lPdbERkd-1s_aF5tUBd9dSaxPNpNOsyg9TjnP0zHFvaYmxcWb8Jn5zsfQbgkWWaAZVDUdXnC5DBBE1AeHDEC2-jsK2MnO3LrVK0b91G5T7Pif9KHNxmWr_UZGACnbvfJ67YOiOD1NrxNrgJs4A_uHZqa9fNSfhcn2kBFRqM0qeu57EhWWiEOY3kxyw89YZGmZ-sfpjezTn5JphFof3ZvEuRw5Fxkr97mN3dwisH1MiCKnru3WNM2g6uz_AU4HHUmjBzYpKwvLgO2Et3rPEksUBJ1SLeBHQCVptzKdqdtsZWt5A9wHhW0z_v1D7QojWTyNDJaxRmOIug6i0XTcI0VIqlRVEjuKucfEXwbDPIZTxiOyGWpQc-Mnlmv2a8dsJ9r40WyYqFzMOgwdLNlEZjXrv3dYf2loi3X86ZMgBXvnoVLk-eC11kbyoLEEuTuxvo8hD9tylEpsHbbBRbJF3m_ApIe9GnVr4iCGVuhcFTF2HUwys1fUCr3sP3y8spdyC-G6xVwywZK6PGtZMtxYdhUZe6g9eoJxV2GGo_oRvyuvERaTjZ7uEeMxIAdMnLpC8FqDZ2ZmJixCQlvmkM0QdEi_m-","summary":[]},"output_index":0,"sequence_number":3}

event: response.output_item.added
data: {"type":"response.output_item.added","item":{"id":"msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb","type":"message","status":"in_progress","content":[],"role":"assistant"},"output_index":1,"sequence_number":4}

event: response.content_part.added
data: {"type":"response.content_part.added","content_index":0,"item_id":"msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb","output_index":1,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":""},"sequence_number":5}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"Hello","item_id":"msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb","logprobs":[],"obfuscation":"TBVr94px2Fc","output_index":1,"sequence_number":6}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":",","item_id":"msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb","logprobs":[],"obfuscation":"17qozVYbf2eeAoc","output_index":1,"sequence_number":7}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":" World","item_id":"msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb","logprobs":[],"obfuscation":"O642Kk6nsU","output_index":1,"sequence_number":8}

event: response.output_text.delta
data: {"type":"response.output_text.delta","content_index":0,"delta":"!","item_id":"msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb","logprobs":[],"obfuscation":"E98lTmzID7yqHVr","output_index":1,"sequence_number":9}

event: response.output_text.done
data: {"type":"response.output_text.done","content_index":0,"item_id":"msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb","logprobs":[],"output_index":1,"sequence_number":10,"text":"Hello, World!"}

event: response.content_part.done
data: {"type":"response.content_part.done","content_index":0,"item_id":"msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb","output_index":1,"part":{"type":"output_text","annotations":[],"logprobs":[],"text":"Hello, World!"},"sequence_number":11}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"id":"msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"Hello, World!"}],"role":"assistant"},"output_index":1,"sequence_number":12}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_04e21c25f1df9e70016968ca712e60819d94c98ca6e7d90576","object":"response","created_at":1768475249,"status":"completed","background":false,"completed_at":1768475250,"error":null,"frequency_penalty":0.0,"incomplete_details":null,"instructions":"Reply with exactly: Hello, World!","max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[{"id":"rs_04e21c25f1df9e70016968ca71ce0c819da13ed36ddaf37baa","type":"reasoning","encrypted_content":"gAAAAABpaMpy0m_2ipP4XwNMNXeuoG0hSrbwu3rLqoGb3XBKq5AvK_arrM0v_yrWKJTAONG8B8FA8aQ0GKpHgrNXI0E7Rny33J5PQwePqc8b0QAK461aYYZGzvkJ3d5GoWwfABiolU-0CZ_hqR7sTd-isCG4Hu7oddH1tLavGM5D4xVHv5CChhkbu008xF_yuzsJJBHxdZaQkvp0uL447Ym9O9ledK_dDNnVLM_wF4x1HFrG7c-gwLbhAAFDU9OM48LBjnCy-weHKNoBZZl-d3YWYuaw2zPkFjcnW__FXaIRqNm4x62kTEMInE2CnFUUw9gA724l2VrBZtYV-laXDCBLU_xNEuaBDS_mPwO5fTf_5G8YI1W8VidX9fb8pBA9WQsu978-AtejYdXIkVGvVh6DfQKwRoNQCvjtH6m5ye1gYn04qNiEvdkvcOiSPcoNtoUkAkFMKgUGb5recUVhWtXnQgLsRQB1xgDYb4LpQYWROWGX8wYmadNPtgLv2Z1avw9QQmZyQhf04s_mK_NNVnWtFZR3UyeUA8ODAjlIS_Rpm460RgQGlX2tm-tL7CjXyEorDpeWxQN9a_iqHoSjlEdWuuUkT_rAuxL9M2y5Woi-LavfUCVOQzA3NMegU1fp74bfh4xh3tkHXcFJRYw-r5f0ENP1erwJB4X8HrzNAOAd279gAOJicLsKnXI3ZDpMSgDVxFFB_4PPOH4wUJAmIDQcpuo7tWJNLY6w-nIdcj8P1iOM_hczx9g86N47NfJ30YKJm_VseC8GtE6v4rSABedE0qFA14_zUETmPcniSHFEUXnBXnk4Bz6MZARHyeEDByXkiYcDT7YOGkiWGH1bnHaIDM0j9Le8ouX0s8NH83eUfcmNfxMm1Gype4s6lwTaDrSvTpHQMWoM","summary":[]},{"id":"msg_04e21c25f1df9e70016968ca722660819da8b53c713113f3bb","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"Hello, World!"}],"role":"assistant"}],"parallel_tool_calls":true,"presence_penalty":0.0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"low","summary":"detailed"},"safety_identifier":null,"service_tier":"default","store":false,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":19,"input_tokens_details":{"cached_tokens":0},"output_tokens":21,"output_tokens_details":{"reasoning_tokens":11},"total_tokens":40},"user":null,"metadata":{}},"sequence_number":13}
"""#
