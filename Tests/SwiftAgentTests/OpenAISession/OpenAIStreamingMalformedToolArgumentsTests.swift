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

@Suite("OpenAI - Streaming - Tool Calls (Malformed Arguments)")
struct OpenAIStreamingMalformedToolArgumentsTests {
  // MARK: - Properties

  private let session: OpenAISession<SessionSchema>

  // MARK: - Initialization

  init() async {
    let mockHTTPClient = ReplayHTTPClient<CreateModelResponseQuery>(
      recordedResponse: .init(body: malformedArgumentsResponse),
    )
    let configuration = OpenAIConfiguration(httpClient: mockHTTPClient)

    session = OpenAISession(
      schema: SessionSchema(),
      instructions: "",
      configuration: configuration,
    )
  }

  @Test("Invalid function_call arguments JSON surfaces a decoding streamingFailure")
  func invalidToolArgumentsSurfaceDecodingFailure() async throws {
    let stream = try session.streamResponse(
      to: "prompt",
      using: .gpt4o,
      options: .init(
        minimumStreamingSnapshotInterval: .zero,
      ),
    )

    do {
      for try await _ in stream {}
      Issue.record("Expected streamResponse to throw")
    } catch {
      guard let generationError = error as? GenerationError else {
        Issue.record("Expected GenerationError but received \(error)")
        return
      }

      switch generationError {
      case let .streamingFailure(context):
        #expect(context.reason == .decodingFailure)
        #expect(context.detail?.contains("tool arguments") == true)
      default:
        Issue.record("Expected GenerationError.streamingFailure but received \(generationError)")
      }
    }
  }
}

// MARK: - Tool

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

// MARK: - Fixture

private let malformedArgumentsResponse: String = #"""
event: response.output_item.added
data: {"type":"response.output_item.added","item":{"id":"fc_bad_arguments","type":"function_call","status":"in_progress","arguments":"","call_id":"call_bad_arguments","name":"get_weather"},"output_index":0,"sequence_number":0}

event: response.function_call_arguments.done
data: {"type":"response.function_call_arguments.done","arguments":"{\"location\": [}","item_id":"fc_bad_arguments","output_index":0,"sequence_number":1}


"""#
