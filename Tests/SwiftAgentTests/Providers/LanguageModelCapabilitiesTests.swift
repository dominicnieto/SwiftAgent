import Foundation
import Testing

@testable import SwiftAgent

struct LanguageModelCapabilitiesTests {
  @Test func directProviderCapabilitiesExposeAgentGradeFeatureFlags() {
    let openAIResponses = OpenAILanguageModel(apiKey: "test-key", model: "gpt-test", apiVariant: .responses)
    let openResponses = OpenResponsesLanguageModel(
      baseURL: URL(string: "https://example.com/v1/")!,
      apiKey: "test-key",
      model: "openai/gpt-test",
    )
    let anthropic = AnthropicLanguageModel(apiKey: "test-key", model: "claude-test")

    #expect(openAIResponses.capabilities.provider.contains(.toolCallStreaming))
    #expect(openAIResponses.capabilities.provider.contains(.encryptedReasoningContinuity))
    #expect(openResponses.capabilities.provider.contains(.responseContinuation))
    #expect(anthropic.capabilities.provider.contains(.structuredStreaming))
    #expect(anthropic.capabilities.provider.contains(.streamingTokenUsage))
  }

  @Test func imageTranscriptSegmentsRoundTripAndPreserveSource() throws {
    let image = Transcript.ImageSegment(
      id: "image-1",
      url: URL(string: "https://example.com/image.png")!,
    )
    let transcript = Transcript(entries: [
      .response(.init(id: "response-1", segments: [.image(image)], status: .completed)),
    ])

    let data = try JSONEncoder().encode(transcript)
    let decoded = try JSONDecoder().decode(Transcript.self, from: data)

    guard case let .response(response) = decoded.entries.first else {
      Issue.record("Expected decoded response entry")
      return
    }
    guard case let .image(decodedImage) = response.segments.first else {
      Issue.record("Expected decoded image segment")
      return
    }

    #expect(decodedImage.id == "image-1")
    #expect(decodedImage.source == .url(URL(string: "https://example.com/image.png")!))
  }

  @Test func partialStructuredGenerationUsesPartialJSONDecoder() throws {
    let partial = try #require(partialStructuredGeneration(
      from: #"{"name":"Spokane""#,
      as: GeneratedContent.self,
    ))

    guard case let .structure(properties, _) = partial.rawContent.kind else {
      Issue.record("Expected partial structured content")
      return
    }

    #expect(properties["name"]?.kind == .string("Spokane"))
  }
}
