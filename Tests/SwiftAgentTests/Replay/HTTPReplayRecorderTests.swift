// By Dennis Müller

import EventSource
import Foundation
@testable import SwiftAgent
import Testing

@Suite("Networking - HTTPReplayRecorder")
struct HTTPReplayRecorderTests {
  @Test("SSE encoding round-trips EventSource.Event")
  func sseEncodingRoundTrip() async throws {
    let input = """
    id: 1
    event: message
    data: line1
    data: line2
    data:
    retry: 123
    """

    let parsed = await parseEvents(from: input)
    let original = try #require(parsed.first)

    let encoded = SSEEventTextEncoder.encode(original)
    let roundTripped = await parseEvents(from: encoded)
    let decoded = try #require(roundTripped.first)

    #expect(decoded == original)
  }

  @Test("Recorder prints paste-ready fixtures")
  func recorderFixtureSnippet() async throws {
    let recorder = HTTPReplayRecorder(
      options: .init(
        includeRequests: true,
        includeHeaders: true,
        prettyPrintJSON: true,
      ),
    )

    let requestID = UUID()
    let url = try #require(URL(string: "https://example.com/v1/responses"))

    await recorder.record(
      request: HTTPRequestSnapshot(
        id: requestID,
        url: url,
        method: "POST",
        headers: [
          "Authorization": "Bearer secret",
          "Content-Type": "application/json",
        ],
        body: Data(#"{"a":1}"#.utf8),
        isRetry: false,
      ),
    )

    await recorder.record(
      streamResponse: HTTPStreamResponseSnapshot(
        requestID: requestID,
        url: url,
        statusCode: 200,
        headers: [:],
        body: """
        event: message
        data: {"ok":true}
        """,
        isRetry: false,
      ),
    )

    let snippet = await recorder.swiftFixtureSnippet(
      accessLevel: .private,
      requestNamePrefix: "request",
      responseNamePrefix: "response",
    )

    #expect(snippet.contains("private let request1: String ="))
    #expect(snippet.contains("private let response1: String ="))
    #expect(snippet.contains(".init(body: response1)"))

    #expect(snippet.contains("Authorization: <redacted>"))
    #expect(snippet.contains(#""a" : 1"#))
    #expect(snippet.contains("event: message"))
  }

  private func parseEvents(from input: String) async -> [EventSource.Event] {
    let parser = EventSource.Parser()
    for byte in input.utf8 {
      await parser.consume(byte)
    }
    await parser.finish()

    var events: [EventSource.Event] = []
    while let event = await parser.getNextEvent() {
      events.append(event)
    }

    return events
  }
}
