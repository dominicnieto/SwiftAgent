import AsyncHTTPClient
import EventSource
import Foundation
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import SwiftAgent

/// SwiftAgent HTTP transport backed by swift-server AsyncHTTPClient.
public final class AsyncHTTPClientTransport: SwiftAgent.HTTPClient {
  private let configuration: HTTPClientConfiguration
  private let client: AsyncHTTPClient.HTTPClient

  public init(configuration: HTTPClientConfiguration, client: AsyncHTTPClient.HTTPClient = .shared) {
    self.configuration = configuration
    self.client = client
  }

  public func send<ResponseBody: Decodable>(
    path: String,
    method: SwiftAgent.HTTPMethod,
    queryItems: [URLQueryItem]?,
    headers: [String: String]?,
    body: (some Encodable & Sendable)?,
    responseType: ResponseBody.Type,
  ) async throws -> ResponseBody {
    let bodyData = try body.map { try configuration.jsonEncoder.encode($0) }
    let request = try await makePreparedURLRequest(
      path: path,
      method: method,
      queryItems: queryItems,
      headers: headers ?? [:],
      body: bodyData,
      accept: "application/json",
    )

    let requestID = UUID()
    await recordRequest(request, requestID: requestID, isRetry: false)

    let (data, response) = try await execute(request)
    await recordResponse(data, response: response, requestID: requestID, isRetry: false)

    if response.statusCode == 401,
       let onUnauthorized = configuration.interceptors.onUnauthorized,
       await onUnauthorized(response, data, request) {
      var retryRequest = request
      if let prepare = configuration.interceptors.prepareRequest {
        try await prepare(&retryRequest)
      }

      let retryRequestID = UUID()
      await recordRequest(retryRequest, requestID: retryRequestID, isRetry: true)
      let (retryData, retryResponse) = try await execute(retryRequest)
      await recordResponse(retryData, response: retryResponse, requestID: retryRequestID, isRetry: true)
      return try decode(responseType, data: retryData, response: retryResponse)
    }

    return try decode(responseType, data: data, response: response)
  }

  public func stream(
    path: String,
    method: SwiftAgent.HTTPMethod,
    headers: [String: String],
    body: (some Encodable & Sendable)?,
  ) -> AsyncThrowingStream<EventSource.Event, any Error> {
    let encodedBodyResult = Result<Data?, any Error> {
      try body.map { try configuration.jsonEncoder.encode($0) }
    }

    return AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
      let task = Task {
        do {
          let bodyData = try encodedBodyResult.get()
          let request = try await makePreparedURLRequest(
            path: path,
            method: method,
            queryItems: nil,
            headers: headers,
            body: bodyData,
            accept: "text/event-stream",
          )

          let requestID = UUID()
          await recordRequest(request, requestID: requestID, isRetry: false)

          var (response, bodyStream) = try await executeStreaming(request)
          var activeRequest = request
          var activeRequestID = requestID
          var isRetry = false

          if response.statusCode == 401,
             let onUnauthorized = configuration.interceptors.onUnauthorized,
             await onUnauthorized(response, nil, request) {
            var retryRequest = request
            if let prepare = configuration.interceptors.prepareRequest {
              try await prepare(&retryRequest)
            }
            activeRequest = retryRequest
            activeRequestID = UUID()
            isRetry = true
            await recordRequest(retryRequest, requestID: activeRequestID, isRetry: true)
            (response, bodyStream) = try await executeStreaming(retryRequest)
          }

          guard (200..<300).contains(response.statusCode) else {
            let errorData = try await collectBody(bodyStream, limit: 4 * 1024)
            await recordResponse(errorData, response: response, requestID: activeRequestID, isRetry: isRetry)
            throw HTTPError.unacceptableStatus(code: response.statusCode, data: errorData)
          }

          let shouldRecordStreamBody = configuration.interceptors.onStreamResponse != nil
          var collectedBytes = Data()
          if shouldRecordStreamBody {
            collectedBytes.reserveCapacity(32 * 1024)
          }

          let parser = EventSource.Parser()

          func flushParsedEvents() async {
            while let event = await parser.getNextEvent() {
              continuation.yield(event)
            }
          }

          do {
            for try await buffer in bodyStream {
              try Task.checkCancellation()
              for byte in buffer.readableBytesView {
                if shouldRecordStreamBody {
                  collectedBytes.append(byte)
                }
                await parser.consume(byte)
                if byte == 0x0A || byte == 0x0D {
                  await flushParsedEvents()
                }
              }
            }

            await parser.finish()
            await flushParsedEvents()

            if shouldRecordStreamBody {
              await recordStreamResponse(
                collectedBytes,
                response: response,
                requestID: activeRequestID,
                isRetry: isRetry,
              )
            }

            continuation.finish()
          } catch {
            await parser.finish()
            await flushParsedEvents()
            if shouldRecordStreamBody {
              await recordStreamResponse(
                collectedBytes,
                response: response,
                requestID: activeRequestID,
                isRetry: isRetry,
              )
            }
            throw error
          }

          _ = activeRequest
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }
}

private extension AsyncHTTPClientTransport {
  func makePreparedURLRequest(
    path: String,
    method: SwiftAgent.HTTPMethod,
    queryItems: [URLQueryItem]?,
    headers: [String: String],
    body: Data?,
    accept: String,
  ) async throws -> URLRequest {
    let url = try makeURL(path: path, queryItems: queryItems)
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    request.setValue(accept, forHTTPHeaderField: "Accept")
    if body != nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    for (key, value) in configuration.defaultHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }

    request.httpBody = body

    if let prepare = configuration.interceptors.prepareRequest {
      try await prepare(&request)
    }

    return request
  }

  func makeURL(path: String, queryItems: [URLQueryItem]?) throws -> URL {
    guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
      throw HTTPError.invalidURL
    }

    let basePath = (components.path as NSString).standardizingPath
    let requestPath = ("/" + path).replacingOccurrences(of: "//", with: "/")
    components.path = (basePath + "/" + requestPath).replacingOccurrences(of: "//", with: "/")
    components.queryItems = queryItems

    guard let url = components.url else {
      throw HTTPError.invalidURL
    }
    return url
  }

  func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let clientRequest = try makeClientRequest(from: request)
    let response = try await client.execute(clientRequest, timeout: .seconds(Int64(configuration.timeout)))
    let data = try await Data(buffer: response.body.collect(upTo: 1024 * 1024 * 64))
    let httpResponse = makeHTTPURLResponse(for: request, statusCode: Int(response.status.code), headers: response.headers)
    return (data, httpResponse)
  }

  func executeStreaming(_ request: URLRequest) async throws -> (HTTPURLResponse, HTTPClientResponse.Body) {
    let clientRequest = try makeClientRequest(from: request)
    let response = try await client.execute(clientRequest, timeout: .seconds(Int64(configuration.timeout)))
    let httpResponse = makeHTTPURLResponse(for: request, statusCode: Int(response.status.code), headers: response.headers)
    return (httpResponse, response.body)
  }

  func makeClientRequest(from request: URLRequest) throws -> HTTPClientRequest {
    guard let url = request.url else {
      throw HTTPError.invalidURL
    }

    var clientRequest = HTTPClientRequest(url: url.absoluteString)
    if let method = request.httpMethod {
      clientRequest.method = .init(rawValue: method)
    }
    for (key, value) in request.allHTTPHeaderFields ?? [:] {
      clientRequest.headers.add(name: key, value: value)
    }
    if let body = request.httpBody {
      clientRequest.body = .bytes(ByteBuffer(data: body))
    }
    return clientRequest
  }

  func decode<ResponseBody: Decodable>(
    _ type: ResponseBody.Type,
    data: Data,
    response: HTTPURLResponse,
  ) throws -> ResponseBody {
    guard (200..<300).contains(response.statusCode) else {
      throw HTTPError.unacceptableStatus(code: response.statusCode, data: data)
    }

    do {
      return try configuration.jsonDecoder.decode(type, from: data)
    } catch let error as DecodingError {
      throw HTTPError.decodingFailed(underlying: error, data: data)
    }
  }

  func makeHTTPURLResponse(
    for request: URLRequest,
    statusCode: Int,
    headers: HTTPHeaders,
  ) -> HTTPURLResponse {
    let headerFields = Dictionary(uniqueKeysWithValues: headers.map { ($0.name, $0.value) })
    return HTTPURLResponse(
      url: request.url ?? configuration.baseURL,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: headerFields,
    )!
  }

  func collectBody(_ body: HTTPClientResponse.Body, limit: Int) async throws -> Data {
    var collected = Data()
    collected.reserveCapacity(limit)
    for try await buffer in body {
      for byte in buffer.readableBytesView {
        if collected.count >= limit {
          return collected
        }
        collected.append(byte)
      }
    }
    return collected
  }

  func recordRequest(_ request: URLRequest, requestID: UUID, isRetry: Bool) async {
    guard let hook = configuration.interceptors.onRequest, let url = request.url else {
      return
    }

    await hook(HTTPRequestSnapshot(
      id: requestID,
      url: url,
      method: request.httpMethod ?? "GET",
      headers: request.allHTTPHeaderFields ?? [:],
      body: request.httpBody,
      isRetry: isRetry,
    ))
  }

  func recordResponse(_ data: Data, response: HTTPURLResponse, requestID: UUID, isRetry: Bool) async {
    guard let hook = configuration.interceptors.onResponse else {
      return
    }

    await hook(HTTPResponseSnapshot(
      requestID: requestID,
      url: response.url ?? configuration.baseURL,
      statusCode: response.statusCode,
      headers: response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
        result[String(describing: pair.key)] = String(describing: pair.value)
      },
      body: data,
      isRetry: isRetry,
    ))
  }

  func recordStreamResponse(_ data: Data, response: HTTPURLResponse, requestID: UUID, isRetry: Bool) async {
    guard let hook = configuration.interceptors.onStreamResponse else {
      return
    }

    await hook(HTTPStreamResponseSnapshot(
      requestID: requestID,
      url: response.url ?? configuration.baseURL,
      statusCode: response.statusCode,
      headers: response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
        result[String(describing: pair.key)] = String(describing: pair.value)
      },
      body: String(decoding: data, as: UTF8.self),
      isRetry: isRetry,
    ))
  }
}
