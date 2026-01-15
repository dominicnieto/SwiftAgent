// By Dennis Müller

import Foundation

/// Records HTTP requests and responses and emits paste-ready Swift fixtures.
///
/// Primary use: create `ReplayHTTPClient.RecordedResponse` fixtures for unit tests.
///
/// This recorder is intentionally isolated from the rest of the SDK. You opt-in by
/// attaching it to ``HTTPClientInterceptors`` (see ``HTTPClientInterceptors/recording(to:)``).
///
/// ## Example
///
/// ```swift
/// let recorder = HTTPReplayRecorder(options: .init(includeRequests: true))
///
/// var interceptors = HTTPClientInterceptors(
///   prepareRequest: { request in
///     request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
///   }
/// )
/// interceptors = interceptors.recording(to: recorder)
///
/// let config = HTTPClientConfiguration(
///   baseURL: URL(string: "https://api.openai.com")!,
///   interceptors: interceptors
/// )
/// let httpClient = URLSessionHTTPClient(configuration: config)
///
/// // Run your session/adapter calls here...
///
/// await recorder.printSwiftFixtureSnippet()
/// ```
///
/// The printed snippet includes `#""" ... """#` raw string literals for each response and
/// a `[ .init(body: response1), ... ]` array ready to paste into tests.
///
/// - Important: Streaming responses are captured as the raw `text/event-stream` payload.
///   If the consumer stops iterating early, the captured payload may be partial.
///   Enabling stream capture buffers stream bytes in memory.
public actor HTTPReplayRecorder {
  /// Options that control what gets printed and how payloads are formatted.
  public struct Options: Sendable {
    /// Print request bodies as additional fixtures.
    public var includeRequests: Bool
    /// Print request headers (redacted) as `//` comments.
    public var includeHeaders: Bool
    /// Pretty-print JSON bodies when possible.
    public var prettyPrintJSON: Bool

    /// Creates a new set of recorder options.
    ///
    /// - Parameters:
    ///   - includeRequests: When `true`, prints request bodies as additional fixtures.
    ///   - includeHeaders: When `true`, prints request headers as redacted `//` comments.
    ///   - prettyPrintJSON: When `true`, pretty-prints JSON bodies when possible.
    public init(
      includeRequests: Bool = false,
      includeHeaders: Bool = false,
      prettyPrintJSON: Bool = true,
    ) {
      self.includeRequests = includeRequests
      self.includeHeaders = includeHeaders
      self.prettyPrintJSON = prettyPrintJSON
    }
  }

  /// Access level used for the generated Swift fixture declarations.
  public enum SwiftAccessLevel: String, Sendable {
    /// A `private` Swift declaration.
    case `private`
    /// A `fileprivate` Swift declaration.
    case `fileprivate`
    /// An `internal` Swift declaration.
    case `internal`
    /// A `package` Swift declaration.
    case package
    /// A `public` Swift declaration.
    case `public`
  }

  /// Recorded response payload that can be printed as a test fixture.
  public struct RecordedResponse: Sendable {
    public enum Kind: Sendable {
      /// A standard JSON HTTP response.
      case http
      /// A streaming `text/event-stream` response.
      case sseStream
    }

    /// Whether this fixture came from an HTTP request or an SSE stream.
    public var kind: Kind
    /// The correlated request snapshot, if available.
    public var request: HTTPRequestSnapshot?
    /// HTTP status code.
    public var statusCode: Int
    /// Raw body bytes (UTF-8 JSON or raw SSE payload).
    public var body: Data

    public init(
      kind: Kind,
      request: HTTPRequestSnapshot?,
      statusCode: Int,
      body: Data,
    ) {
      self.kind = kind
      self.request = request
      self.statusCode = statusCode
      self.body = body
    }
  }

  private let options: Options
  private var requestOrder: [HTTPRequestSnapshot] = []
  private var requestsByID: [UUID: HTTPRequestSnapshot] = [:]
  private var responses: [RecordedResponse] = []

  public init(options: Options = .init()) {
    self.options = options
  }

  /// Records an outgoing request snapshot.
  ///
  /// You typically don't call this directly. Prefer attaching the recorder via
  /// ``HTTPClientInterceptors/recording(to:)``.
  public func record(request: HTTPRequestSnapshot) {
    requestOrder.append(request)
    requestsByID[request.id] = request
  }

  /// Records a non-streaming (standard) HTTP response snapshot.
  ///
  /// You typically don't call this directly. Prefer attaching the recorder via
  /// ``HTTPClientInterceptors/recording(to:)``.
  public func record(response: HTTPResponseSnapshot) {
    let request = requestsByID[response.requestID]
    responses.append(
      RecordedResponse(
        kind: .http,
        request: request,
        statusCode: response.statusCode,
        body: response.body ?? Data(),
      ),
    )
  }

  /// Records a streaming Server-Sent Events (SSE) response snapshot.
  ///
  /// You typically don't call this directly. Prefer attaching the recorder via
  /// ``HTTPClientInterceptors/recording(to:)``.
  public func record(streamResponse: HTTPStreamResponseSnapshot) {
    let request = requestsByID[streamResponse.requestID]
    responses.append(
      RecordedResponse(
        kind: .sseStream,
        request: request,
        statusCode: streamResponse.statusCode,
        body: Data(streamResponse.body.utf8),
      ),
    )
  }

  /// Clears all recorded requests and responses.
  public func reset() {
    requestOrder = []
    requestsByID = [:]
    responses = []
  }

  /// Returns all recorded responses in the order they were observed.
  public func recordedResponses() -> [RecordedResponse] {
    responses
  }

  /// Prints a paste-ready Swift snippet to stdout.
  ///
  /// The output contains:
  /// - `#""" ... """#` raw string constants for each response (and optionally request body)
  /// - a `[ .init(body: response1), ... ]` array ready for `ReplayHTTPClient(recordedResponses:)`
  public func printSwiftFixtureSnippet(
    accessLevel: SwiftAccessLevel = .private,
    requestNamePrefix: String = "request",
    responseNamePrefix: String = "response",
  ) {
    print(
      swiftFixtureSnippet(
        accessLevel: accessLevel,
        requestNamePrefix: requestNamePrefix,
        responseNamePrefix: responseNamePrefix,
      ),
    )
  }

  /// Returns a paste-ready Swift snippet as a string.
  ///
  /// This is the same content as ``printSwiftFixtureSnippet(accessLevel:requestNamePrefix:responseNamePrefix:)``,
  /// but returned instead of printed.
  public func swiftFixtureSnippet(
    accessLevel: SwiftAccessLevel = .private,
    requestNamePrefix: String = "request",
    responseNamePrefix: String = "response",
  ) -> String {
    var lines: [String] = []

    if options.includeRequests, !requestOrder.isEmpty {
      lines.append("// MARK: - Recorded Requests")
      lines.append("")

      for (index, request) in requestOrder.enumerated() {
        let name = "\(requestNamePrefix)\(index + 1)"
        lines.append("// \(request.method) \(request.url.absoluteString)")

        if options.includeHeaders, !request.headers.isEmpty {
          lines.append("// headers:")
          for (key, value) in redactHeaders(request.headers).sorted(by: { $0.key < $1.key }) {
            lines.append("//   \(key): \(value)")
          }
        }

        let bodyString = formatBody(request.body, prettyPrintJSON: options.prettyPrintJSON)
        lines.append("\(accessLevel.rawValue) let \(name): String = \(swiftStringLiteral(bodyString))")
        lines.append("")
      }
    }

    lines.append("// MARK: - Recorded Responses")
    lines.append("")

    for (index, response) in responses.enumerated() {
      let name = "\(responseNamePrefix)\(index + 1)"

      if let request = response.request {
        var comment = "// \(request.method) \(request.url.absoluteString)"
        if response.kind == .sseStream {
          comment += " (stream)"
        }
        if response.statusCode != 200 {
          comment += " -> \(response.statusCode)"
        }
        if request.isRetry {
          comment += " (retry)"
        }
        lines.append(comment)
      }

      let bodyString = formatBody(response.body, prettyPrintJSON: options.prettyPrintJSON)
      lines.append("\(accessLevel.rawValue) let \(name): String = \(swiftStringLiteral(bodyString))")
      lines.append("")
    }

    if !responses.isEmpty {
      lines.append("// Paste into `ReplayHTTPClient(recordedResponses:)`")
      lines.append("[")

      for (index, response) in responses.enumerated() {
        let name = "\(responseNamePrefix)\(index + 1)"
        if response.statusCode == 200 {
          lines.append("  .init(body: \(name)),")
        } else {
          lines.append("  .init(body: \(name), statusCode: \(response.statusCode)),")
        }
      }

      lines.append("]")
      lines.append("")
    }

    return lines.joined(separator: "\n")
  }

  private func formatBody(_ data: Data?, prettyPrintJSON: Bool) -> String {
    guard let data, !data.isEmpty else {
      return ""
    }

    if prettyPrintJSON, let pretty = JSONPrettyPrinter.prettyPrintedJSONString(from: data) {
      return trimTrailingNewlines(pretty)
    }

    if let string = String(data: data, encoding: .utf8) {
      return trimTrailingNewlines(string)
    }

    return trimTrailingNewlines(data.base64EncodedString())
  }

  private func formatBody(_ data: Data, prettyPrintJSON: Bool) -> String {
    formatBody(Optional(data), prettyPrintJSON: prettyPrintJSON)
  }

  private func redactHeaders(_ headers: [String: String]) -> [String: String] {
    var redacted = headers
    for (key, value) in headers {
      let lowercased = key.lowercased()

      if lowercased == "authorization" {
        redacted[key] = "<redacted>"
        continue
      }

      if lowercased.contains("api-key") || lowercased.contains("apikey") {
        redacted[key] = "<redacted>"
        continue
      }

      redacted[key] = value
    }
    return redacted
  }
}

public extension HTTPClientInterceptors {
  /// Returns a copy of these interceptors with recording enabled.
  ///
  /// Existing hooks are preserved and run before the recorder is notified.
  ///
  /// - Important: For SSE streams, recording is only active if you also configure
  ///   ``HTTPClientInterceptors/onStreamResponse`` (this helper does that for you).
  ///   When enabled, the SDK buffers stream bytes in memory (payload may be partial if the
  ///   consumer stops iterating early).
  func recording(to recorder: HTTPReplayRecorder) -> HTTPClientInterceptors {
    let existingOnRequest = onRequest
    let existingOnResponse = onResponse
    let existingOnStreamResponse = onStreamResponse

    return HTTPClientInterceptors(
      prepareRequest: prepareRequest,
      onUnauthorized: onUnauthorized,
      onRequest: { request in
        if let existingOnRequest {
          await existingOnRequest(request)
        }
        await recorder.record(request: request)
      },
      onResponse: { response in
        if let existingOnResponse {
          await existingOnResponse(response)
        }
        await recorder.record(response: response)
      },
      onStreamResponse: { response in
        if let existingOnStreamResponse {
          await existingOnStreamResponse(response)
        }
        await recorder.record(streamResponse: response)
      },
    )
  }
}

private enum JSONPrettyPrinter {
  static func prettyPrintedJSONString(from data: Data) -> String? {
    do {
      let object = try JSONSerialization.jsonObject(with: data)
      let prettyData = try JSONSerialization.data(
        withJSONObject: object,
        options: [
          .prettyPrinted,
          .sortedKeys,
        ],
      )
      return String(data: prettyData, encoding: .utf8)
    } catch {
      return nil
    }
  }
}

private enum SwiftStringLiteral {
  static func multilineRawString(_ content: String) -> String {
    let trimmed = trimTrailingNewlines(content)

    if trimmed.isEmpty {
      return "\"\""
    }

    var poundCount = 1
    while true {
      let pounds = String(repeating: "#", count: poundCount)
      let terminator = "\"\"\"\(pounds)"
      let interpolationStart = "\\\(pounds)("

      if trimmed.contains(terminator) || trimmed.contains(interpolationStart) {
        poundCount += 1
        continue
      }

      let start = "\(pounds)\"\"\""
      let end = "\"\"\"\(pounds)"
      return [
        start,
        trimmed,
        end,
      ].joined(separator: "\n")
    }
  }
}

private func swiftStringLiteral(_ content: String) -> String {
  SwiftStringLiteral.multilineRawString(content)
}

private func trimTrailingNewlines(_ input: String) -> String {
  var output = input
  while output.hasSuffix("\n") || output.hasSuffix("\r") {
    output.removeLast()
  }
  return output
}
