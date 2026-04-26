// By Dennis Müller

import EventSource
import Foundation
@testable import SwiftAgent

actor ReplayHTTPClient<RequestBodyType: Encodable & Sendable>: HTTPClient {
  enum ReplayError: Error, LocalizedError {
    case noRecordedResponsesRemaining
    case invalidUTF8RecordedResponse
    case invalidBodyType

    var errorDescription: String? {
      switch self {
      case .noRecordedResponsesRemaining:
        "Attempted to consume more recorded HTTP responses than were provided."
      case .invalidUTF8RecordedResponse:
        "Recorded HTTP response could not be converted to UTF-8 data."
      case .invalidBodyType:
        "Recorded HTTP request body is not of type RequestBodyType."
      }
    }
  }

  nonisolated let makeJSONDecoder: @Sendable () -> JSONDecoder

  struct RecordedResponse: Sendable {
    var body: String
    var statusCode: Int
    var headers: [String: String]
    var delay: Duration?

    init(body: String, statusCode: Int = 200, headers: [String: String] = [:], delay: Duration? = nil) {
      self.body = body
      self.statusCode = statusCode
      self.headers = headers
      self.delay = delay
    }
  }

  struct Request: Sendable {
    var path: String
    var method: HTTPMethod
    var queryItems: [URLQueryItem]?
    var headers: [String: String]?
    var body: RequestBodyType
  }

  private var pendingRecordedResponses: [RecordedResponse]
  private(set) var recordedRequests: [Request] = []

  init(
    recordedResponses: [RecordedResponse],
    makeJSONDecoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() },
  ) {
    pendingRecordedResponses = recordedResponses
    self.makeJSONDecoder = makeJSONDecoder
  }

  init(
    recordedResponse: RecordedResponse,
    makeJSONDecoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() },
  ) {
    pendingRecordedResponses = [recordedResponse]
    self.makeJSONDecoder = makeJSONDecoder
  }

  nonisolated func sendResponse<ResponseBody>(
    path: String,
    method: HTTPMethod,
    queryItems: [URLQueryItem]?,
    headers: [String: String]?,
    body: (some Encodable & Sendable)?,
    responseType: ResponseBody.Type,
  ) async throws -> HTTPClientDecodedResponse<ResponseBody> where ResponseBody: Decodable & Sendable {
    if let body = body as? RequestBodyType {
      await record(path: path, method: method, queryItems: queryItems, headers: headers, body: body)
    } else {
      throw ReplayError.invalidBodyType
    }

    let response = try await takeNextRecordedResponse()

    if let delay = response.delay {
      try await Task.sleep(for: delay)
      try Task.checkCancellation()
    }

    guard let data = response.body.data(using: .utf8) else {
      throw ReplayError.invalidUTF8RecordedResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw HTTPError.unacceptableStatus(code: response.statusCode, data: data)
    }

    let decodedBody = try makeJSONDecoder().decode(ResponseBody.self, from: data)
    return HTTPClientDecodedResponse(
      requestID: UUID(),
      statusCode: response.statusCode,
      headers: response.headers,
      body: decodedBody,
    )
  }

  nonisolated func stream(
    path: String,
    method: HTTPMethod,
    headers: [String: String],
    body: (some Encodable & Sendable)?,
  ) -> AsyncThrowingStream<EventSource.Event, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task<Void, Never> {
        if let body = body as? RequestBodyType {
          await record(path: path, method: method, queryItems: nil, headers: headers, body: body)
        } else {
          continuation.finish(throwing: ReplayError.invalidBodyType)
          return
        }

        do {
          let response = try await takeNextRecordedResponse()
          guard let data = response.body.data(using: .utf8) else {
            throw ReplayError.invalidUTF8RecordedResponse
          }
          guard (200..<300).contains(response.statusCode) else {
            throw HTTPError.unacceptableStatus(code: response.statusCode, data: data)
          }

          for event in await parseEvents(from: response.body) {
            continuation.yield(event)
          }
          continuation.finish()
        } catch {
          continuation.yield(with: .failure(error))
          continuation.finish()
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  nonisolated func streamResponse(
    path: String,
    method: HTTPMethod,
    headers: [String: String],
    body: (some Encodable & Sendable)?,
  ) async throws -> HTTPClientStreamResponse {
    if let body = body as? RequestBodyType {
      await record(path: path, method: method, queryItems: nil, headers: headers, body: body)
    } else {
      throw ReplayError.invalidBodyType
    }

    let response = try await takeNextRecordedResponse()
    guard let data = response.body.data(using: .utf8) else {
      throw ReplayError.invalidUTF8RecordedResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw HTTPError.unacceptableStatus(code: response.statusCode, data: data)
    }

    let events = AsyncThrowingStream<EventSource.Event, any Error> { continuation in
      let task = Task {
        for event in await parseEvents(from: response.body) {
          continuation.yield(event)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }

    return HTTPClientStreamResponse(
      requestID: UUID(),
      statusCode: response.statusCode,
      headers: response.headers,
      events: events,
    )
  }

  nonisolated func recordedRequests() async -> [Request] {
    await recordedRequests
  }
}

private extension ReplayHTTPClient {
  func takeNextRecordedResponse() throws -> RecordedResponse {
    guard let response = pendingRecordedResponses.first else {
      throw ReplayError.noRecordedResponsesRemaining
    }

    pendingRecordedResponses.removeFirst()
    return response
  }

  /// Helper to consume a string and get all dispatched events
  func parseEvents(
    from input: String,
    using parser: EventSource.Parser = EventSource.Parser(),
  ) async -> [EventSource.Event] {
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

  func record(
    path: String,
    method: HTTPMethod,
    queryItems: [URLQueryItem]?,
    headers: [String: String]?,
    body: RequestBodyType,
  ) async {
    recordedRequests.append(
      Request(
        path: path,
        method: method,
        queryItems: queryItems,
        headers: headers,
        body: body,
      ),
    )
  }
}
