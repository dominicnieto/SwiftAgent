import EventSource
import Foundation

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
}
