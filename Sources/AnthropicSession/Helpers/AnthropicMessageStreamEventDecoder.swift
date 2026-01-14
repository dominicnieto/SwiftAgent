// By Dennis Müller

import EventSource
import Foundation
import SwiftAgent
import SwiftAnthropic

struct AnthropicMessageStreamEvent {
  let name: String?
  let payload: MessageStreamResponse

  var type: String {
    if !payload.type.isEmpty {
      return payload.type
    }

    return name ?? ""
  }
}

struct AnthropicMessageStreamEventDecoder {
  private let decoder: JSONDecoder

  init(decoder: JSONDecoder = JSONDecoder()) {
    let localDecoder = decoder
    localDecoder.keyDecodingStrategy = .convertFromSnakeCase
    self.decoder = localDecoder
  }

  func decodeEvent(
    from event: EventSource.Event,
  ) throws -> AnthropicMessageStreamEvent? {
    let trimmed = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }
    guard let data = trimmed.data(using: .utf8) else {
      let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid UTF-8"))
      throw SSEError.decodingFailed(underlying: error, data: Data())
    }

    let payload = try decoder.decode(MessageStreamResponse.self, from: data)
    return AnthropicMessageStreamEvent(name: event.event, payload: payload)
  }
}
