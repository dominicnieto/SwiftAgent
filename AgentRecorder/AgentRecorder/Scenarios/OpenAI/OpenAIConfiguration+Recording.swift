// By Dennis Müller

import Foundation
import SwiftAgent

enum OpenAIRecordingHTTPClient {
  static func make(
    apiKey: String,
    recorder: HTTPReplayRecorder,
  ) -> any HTTPClient {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let decoder = JSONDecoder()

    var interceptors = HTTPClientInterceptors(
      prepareRequest: { request in
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      },
      onUnauthorized: { _, _, _ in
        false
      },
    )
    interceptors = interceptors.recording(to: recorder)

    let configuration = HTTPClientConfiguration(
      baseURL: URL(string: "https://api.openai.com/v1/")!,
      defaultHeaders: [:],
      timeout: 60,
      jsonEncoder: encoder,
      jsonDecoder: decoder,
      interceptors: interceptors,
    )

    let session = RecordingURLSession.make(timeout: configuration.timeout)
    return URLSessionHTTPClient(configuration: configuration, session: session)
  }
}
