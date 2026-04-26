// By Dennis Müller

import EventSource
import Foundation

public extension URLSessionHTTPClient {
  /// Opens a Server-Sent Events stream and returns response headers with the event stream.
  func streamResponse(
    path: String,
    method: HTTPMethod,
    headers: [String: String],
    body: (some Encodable & Sendable)?,
  ) async throws -> HTTPClientStreamResponse {
    let requestBody = try body.map { try configuration.jsonEncoder.encode($0) }
    let url = try makeURL(path: path, queryItems: nil)
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    if requestBody != nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    for (headerField, headerValue) in configuration.defaultHeaders {
      request.setValue(headerValue, forHTTPHeaderField: headerField)
    }

    for (headerField, headerValue) in headers {
      request.setValue(headerValue, forHTTPHeaderField: headerField)
    }

    request.httpBody = requestBody

    if let prepareRequest = configuration.interceptors.prepareRequest {
      try await prepareRequest(&request)
    }

    var requestID = UUID()
    var isRetry = false
    await recordStreamRequestSnapshotIfNeeded(requestID: requestID, request: request, url: url, method: method, isRetry: false)
    NetworkLog.request(request)

    var (asyncBytes, response) = try await urlSession.bytes(for: request)

    if let httpResponse = response as? HTTPURLResponse,
       httpResponse.statusCode == 401,
       let onUnauthorized = configuration.interceptors.onUnauthorized,
       await onUnauthorized(httpResponse, nil, request) {
      if let prepareRequest = configuration.interceptors.prepareRequest {
        try await prepareRequest(&request)
      }

      requestID = UUID()
      isRetry = true
      await recordStreamRequestSnapshotIfNeeded(requestID: requestID, request: request, url: url, method: method, isRetry: true)
      NetworkLog.request(request)
      (asyncBytes, response) = try await urlSession.bytes(for: request)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw SSEError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      let errorPreview = try await readPrefix(from: asyncBytes, maxLength: 4 * 1024)
      NetworkLog.response(response, data: errorPreview)
      await recordStreamErrorResponseIfNeeded(
        requestID: requestID,
        response: httpResponse,
        data: errorPreview,
        url: url,
        isRetry: isRetry,
      )
      throw HTTPError.unacceptableStatus(code: httpResponse.statusCode, data: errorPreview)
    }

    NetworkLog.response(response, data: nil)
    let streamRequestID = requestID
    let streamIsRetry = isRetry
    let streamStatusCode = httpResponse.statusCode
    let responseHeaders = httpResponse.swiftAgentHeaderFields
    let streamURL = httpResponse.url ?? url
    let shouldRecordStreamBody = configuration.interceptors.onStreamResponse != nil
    let streamAsyncBytes = asyncBytes

    let events = AsyncThrowingStream<EventSource.Event, any Error>(bufferingPolicy: .unbounded) { continuation in
      let task = Task {
        let parser = EventSource.Parser()
        var collectedBytes = Data()
        if shouldRecordStreamBody {
          collectedBytes.reserveCapacity(32 * 1024)
        }

        func flushParsedEvents() async {
          while let event = await parser.getNextEvent() {
            continuation.yield(event)
          }
        }

        func notifyStreamHookIfNeeded() async {
          guard shouldRecordStreamBody, let onStreamResponse = configuration.interceptors.onStreamResponse else {
            return
          }
          await onStreamResponse(HTTPStreamResponseSnapshot(
            requestID: streamRequestID,
            url: streamURL,
            statusCode: streamStatusCode,
            headers: responseHeaders,
            body: String(decoding: collectedBytes, as: UTF8.self),
            isRetry: streamIsRetry,
          ))
        }

        do {
          for try await byte in streamAsyncBytes {
            try Task.checkCancellation()
            if shouldRecordStreamBody {
              collectedBytes.append(byte)
            }
            await parser.consume(byte)
            if byte == 0x0A || byte == 0x0D {
              await flushParsedEvents()
            }
          }
          await parser.finish()
          await flushParsedEvents()
          await notifyStreamHookIfNeeded()
          continuation.finish()
        } catch is CancellationError {
          await parser.finish()
          await flushParsedEvents()
          await notifyStreamHookIfNeeded()
          continuation.finish(throwing: CancellationError())
        } catch {
          await parser.finish()
          await flushParsedEvents()
          await notifyStreamHookIfNeeded()
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in task.cancel() }
    }

    return HTTPClientStreamResponse(
      requestID: streamRequestID,
      statusCode: streamStatusCode,
      headers: responseHeaders,
      events: events,
    )
  }

  // MARK: - Public API (provider-agnostic)

  /// Opens a Server-Sent Events stream and yields `SSEEvent` frames as they arrive.
  ///
  /// - Parameters:
  ///   - path: Relative API path (joined with the client's `baseURL`).
  ///   - method: HTTP method to use. Defaults to `.post` for response streaming APIs.
  ///   - headers: Additional headers. `Accept: text/event-stream` is set automatically.
  ///   - body: Optional JSON body (encoded with the client's JSON encoder).
  /// - Returns: `AsyncThrowingStream<SSEEvent, Error>`.
  func stream(
    path: String,
    method: HTTPMethod = .post,
    headers: [String: String] = [:],
    body: (some Encodable)? = nil,
  ) -> AsyncThrowingStream<EventSource.Event, Error> {
    let encodedBodyResult = Result<Data?, Error> {
      try body.map { try configuration.jsonEncoder.encode($0) }
    }

    // Use explicit unbounded buffering to avoid back‑pressure when callers
    // temporarily pause consumption (e.g. while awaiting tool execution).
    return AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
      let task = Task {
        do {
          let requestBody = try encodedBodyResult.get()
          let url = try makeURL(path: path, queryItems: nil)
          var request = URLRequest(url: url)
          request.httpMethod = method.rawValue
          request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
          if requestBody != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          }

          for (headerField, headerValue) in configuration.defaultHeaders {
            request.setValue(headerValue, forHTTPHeaderField: headerField)
          }

          for (headerField, headerValue) in headers {
            request.setValue(headerValue, forHTTPHeaderField: headerField)
          }

          request.httpBody = requestBody

          if let prepareRequest = configuration.interceptors.prepareRequest {
            try await prepareRequest(&request)
          }

          var requestID = UUID()
          var isRetry = false
          if let onRequest = configuration.interceptors.onRequest {
            let snapshot = HTTPRequestSnapshot(
              id: requestID,
              url: url,
              method: request.httpMethod ?? method.rawValue,
              headers: request.allHTTPHeaderFields ?? [:],
              body: request.httpBody,
              isRetry: false,
            )
            await onRequest(snapshot)
          }

          NetworkLog.request(request)

          var (asyncBytes, response) = try await urlSession.bytes(for: request)

          if let httpResponse = response as? HTTPURLResponse,
             httpResponse.statusCode == 401,
             let onUnauthorized = configuration.interceptors.onUnauthorized,
             await onUnauthorized(httpResponse, nil, request) {
            if let prepareRequest = configuration.interceptors.prepareRequest {
              try await prepareRequest(&request)
            }

            requestID = UUID()
            isRetry = true
            if let onRequest = configuration.interceptors.onRequest {
              let snapshot = HTTPRequestSnapshot(
                id: requestID,
                url: url,
                method: request.httpMethod ?? method.rawValue,
                headers: request.allHTTPHeaderFields ?? [:],
                body: request.httpBody,
                isRetry: true,
              )
              await onRequest(snapshot)
            }
            NetworkLog.request(request)
            (asyncBytes, response) = try await urlSession.bytes(for: request)
          }

          guard let httpResponse = response as? HTTPURLResponse else {
            throw SSEError.invalidResponse
          }
          guard (200..<300).contains(httpResponse.statusCode) else {
            let errorPreview = try await readPrefix(from: asyncBytes, maxLength: 4 * 1024)
            NetworkLog.response(response, data: errorPreview)
            if let onResponse = configuration.interceptors.onResponse {
              let errorURL = httpResponse.url ?? url
              let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
                let key = String(describing: pair.key)
                let value = String(describing: pair.value)
                partialResult[key] = value
              }

              let snapshot = HTTPResponseSnapshot(
                requestID: requestID,
                url: errorURL,
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: errorPreview,
                isRetry: isRetry,
              )

              await onResponse(snapshot)
            }
            throw HTTPError.unacceptableStatus(code: httpResponse.statusCode, data: errorPreview)
          }

          NetworkLog.response(response, data: nil)

          let shouldRecordStreamBody = configuration.interceptors.onStreamResponse != nil
          if shouldRecordStreamBody {
            var collectedBytes = Data()
            collectedBytes.reserveCapacity(32 * 1024)

            let parser = EventSource.Parser()
            let streamURL = httpResponse.url ?? url

            func flushParsedEvents() async {
              while let event = await parser.getNextEvent() {
                continuation.yield(event)
              }
            }

            func notifyStreamHookIfNeeded() async {
              guard let onStreamResponse = configuration.interceptors.onStreamResponse else {
                return
              }

              let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
                let key = String(describing: pair.key)
                let value = String(describing: pair.value)
                partialResult[key] = value
              }

              let rawStreamString = String(decoding: collectedBytes, as: UTF8.self)

              let snapshot = HTTPStreamResponseSnapshot(
                requestID: requestID,
                url: streamURL,
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: rawStreamString,
                isRetry: isRetry,
              )

              await onStreamResponse(snapshot)
            }

            do {
              for try await byte in asyncBytes {
                try Task.checkCancellation()
                collectedBytes.append(byte)
                await parser.consume(byte)

                if byte == 0x0A || byte == 0x0D {
                  await flushParsedEvents()
                }
              }

              await parser.finish()
              await flushParsedEvents()
              await notifyStreamHookIfNeeded()
            } catch is CancellationError {
              await parser.finish()
              await flushParsedEvents()
              await notifyStreamHookIfNeeded()
              throw CancellationError()
            } catch {
              await parser.finish()
              await flushParsedEvents()
              await notifyStreamHookIfNeeded()
              throw error
            }
          } else {
            for try await event in asyncBytes.events {
              try Task.checkCancellation()
              continuation.yield(event)
            }
          }

          continuation.finish()
        } catch is CancellationError {
          continuation.finish(throwing: CancellationError())
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }

  /// Collect up to `maxLength` bytes from an `URLSession.AsyncBytes` stream into `Data`.
  /// Consumes from the stream; intended for error logging where the stream will not be reused.
  private func readPrefix(from bytes: URLSession.AsyncBytes, maxLength: Int) async throws -> Data {
    var collectedBytes = Data()
    collectedBytes.reserveCapacity(maxLength)
    var iterator = bytes.makeAsyncIterator()
    while collectedBytes.count < maxLength, let byte = try await iterator.next() {
      try Task.checkCancellation()
      collectedBytes.append(byte)
    }
    return collectedBytes
  }

  private func recordStreamRequestSnapshotIfNeeded(
    requestID: UUID,
    request: URLRequest,
    url: URL,
    method: HTTPMethod,
    isRetry: Bool,
  ) async {
    guard let onRequest = configuration.interceptors.onRequest else {
      return
    }
    await onRequest(HTTPRequestSnapshot(
      id: requestID,
      url: url,
      method: request.httpMethod ?? method.rawValue,
      headers: request.allHTTPHeaderFields ?? [:],
      body: request.httpBody,
      isRetry: isRetry,
    ))
  }

  private func recordStreamErrorResponseIfNeeded(
    requestID: UUID,
    response: HTTPURLResponse,
    data: Data?,
    url: URL,
    isRetry: Bool,
  ) async {
    guard let onResponse = configuration.interceptors.onResponse else {
      return
    }
    await onResponse(HTTPResponseSnapshot(
      requestID: requestID,
      url: response.url ?? url,
      statusCode: response.statusCode,
      headers: response.swiftAgentHeaderFields,
      body: data,
      isRetry: isRetry,
    ))
  }
}

private extension HTTPURLResponse {
  var swiftAgentHeaderFields: [String: String] {
    allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
      partialResult[String(describing: pair.key)] = String(describing: pair.value)
    }
  }
}

/// Errors that can occur while working with Server-Sent Events streams.
public enum SSEError: Error, LocalizedError, Sendable {
  case invalidResponse
  case notEventStream(contentType: String?)
  case decodingFailed(underlying: Error, data: Data)

  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      "Invalid response (no HTTPURLResponse)."
    case let .notEventStream(contentType):
      "Expected text/event-stream, got: \(contentType ?? "nil")."
    case let .decodingFailed(underlying, _):
      "Failed to decode SSE data: \(underlying.localizedDescription)"
    }
  }
}
