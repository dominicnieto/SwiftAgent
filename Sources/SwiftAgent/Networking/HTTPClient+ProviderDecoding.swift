import EventSource
import Foundation

/// A decoded SSE stream plus the HTTP metadata observed when opening it.
struct DecodedEventStream<Event: Sendable>: Sendable {
  var requestID: UUID
  var statusCode: Int
  var headers: [String: String]
  var events: AsyncThrowingStream<Event, any Error>
}

extension HTTPClient {
  /// Streams SSE events and decodes each event data payload into a provider event type.
  func decodedEventStream<Event: Decodable & Sendable>(
    path: String,
    method: HTTPMethod = .post,
    headers: [String: String] = [:],
    body: (some Encodable & Sendable)?,
    as eventType: Event.Type,
  ) -> AsyncThrowingStream<Event, any Error> {
    let events = stream(path: path, method: method, headers: headers, body: body)
    return AsyncThrowingStream { continuation in
      let task = Task {
        let decoder = JSONDecoder()
        do {
          for try await event in events {
            guard let data = event.data.data(using: .utf8) else {
              continue
            }
            let decoded = try decoder.decode(eventType, from: data)
            continuation.yield(decoded)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Opens an SSE stream and decodes each event data payload while preserving HTTP metadata.
  func decodedEventStreamResponse<Event: Decodable & Sendable>(
    path: String,
    method: HTTPMethod = .post,
    headers: [String: String] = [:],
    body: (some Encodable & Sendable)?,
    as eventType: Event.Type,
  ) async throws -> DecodedEventStream<Event> {
    let response = try await streamResponse(path: path, method: method, headers: headers, body: body)
    let decodedEvents = AsyncThrowingStream<Event, any Error> { continuation in
      let task = Task {
        let decoder = JSONDecoder()
        do {
          for try await event in response.events {
            guard let data = event.data.data(using: .utf8) else {
              continue
            }
            let decoded = try decoder.decode(eventType, from: data)
            continuation.yield(decoded)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in task.cancel() }
    }

    return DecodedEventStream(
      requestID: response.requestID,
      statusCode: response.statusCode,
      headers: response.headers,
      events: decodedEvents,
    )
  }
}
