// By Dennis Müller

@testable import AnthropicSession
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@Suite("Anthropic - Generation Options Validation")
struct AnthropicGenerationOptionsValidationTests {
  private let session: AnthropicSession<NoSchema>
  private let mockHTTPClient: ReplayHTTPClient<MessageParameter>

  init() async {
    mockHTTPClient = ReplayHTTPClient<MessageParameter>(recordedResponses: [])
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(schema: NoSchema(), instructions: "", configuration: configuration)
  }

  @Test("Missing maxOutputTokens throws before sending a request")
  func missingMaxOutputTokensThrows() async {
    do {
      _ = try await session.respond(
        to: "Hello",
        using: .other("claude-haiku-4-5"),
        options: AnthropicGenerationOptions(),
      )
      Issue.record("Expected AnthropicGenerationOptionsError.missingMaxTokens")
    } catch AnthropicGenerationOptionsError.missingMaxTokens {
      // Expected
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.isEmpty)
  }

  @Test("Thinking budget must be at least 1024")
  func thinkingBudgetTooLowThrows() async {
    let options = AnthropicGenerationOptions(
      maxOutputTokens: 64,
      thinking: .init(budgetTokens: 16),
    )

    do {
      _ = try await session.respond(
        to: "Hello",
        using: .other("claude-haiku-4-5"),
        options: options,
      )
      Issue.record("Expected AnthropicGenerationOptionsError.invalidThinkingBudget")
    } catch let AnthropicGenerationOptionsError.invalidThinkingBudget(value) {
      #expect(value == 16)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.isEmpty)
  }

  @Test("maxOutputTokens must be greater than thinking budget")
  func maxOutputTokensMustExceedThinkingBudget() async {
    let options = AnthropicGenerationOptions(
      maxOutputTokens: 1024,
      thinking: .init(budgetTokens: 1024),
    )

    do {
      _ = try await session.respond(
        to: "Hello",
        using: .other("claude-haiku-4-5"),
        options: options,
      )
      Issue.record("Expected AnthropicGenerationOptionsError.thinkingBudgetExceedsMaxOutputTokens")
    } catch let AnthropicGenerationOptionsError.thinkingBudgetExceedsMaxOutputTokens(
      budgetTokens,
      maxOutputTokens,
    ) {
      #expect(budgetTokens == 1024)
      #expect(maxOutputTokens == 1024)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.isEmpty)
  }
}
