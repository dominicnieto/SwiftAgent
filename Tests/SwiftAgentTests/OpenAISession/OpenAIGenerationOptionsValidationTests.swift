// By Dennis Müller

import FoundationModels
import OpenAI
@testable import OpenAISession
@testable import SwiftAgent
import Testing

@Suite("OpenAI - Generation Options Validation")
struct OpenAIGenerationOptionsValidationTests {
  private let session: OpenAISession<NoSchema>
  private let mockHTTPClient: ReplayHTTPClient<CreateModelResponseQuery>

  init() async {
    mockHTTPClient = ReplayHTTPClient<CreateModelResponseQuery>(recordedResponses: [])
    let configuration = OpenAIConfiguration(httpClient: mockHTTPClient)
    session = OpenAISession(schema: NoSchema(), instructions: "", configuration: configuration)
  }

  @Test("Missing encrypted reasoning throws before sending a request")
  func missingEncryptedReasoningThrowsBeforeSendingRequest() async {
    do {
      _ = try await session.respond(
        to: "Hello",
        using: .gpt5_2,
        options: OpenAIGenerationOptions(),
      )
      Issue.record("Expected OpenAIGenerationOptionsError.missingEncryptedReasoningForReasoningModel")
    } catch OpenAIGenerationOptionsError.missingEncryptedReasoningForReasoningModel {
      // Expected
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.isEmpty)
  }
}
