// By Dennis Müller

import EventSource
import Foundation

enum SSEEventTextEncoder {
  static func encode(_ event: EventSource.Event) -> String {
    var lines: [String] = []
    lines.reserveCapacity(4)

    if let id = event.id {
      lines.append("id: \(id)")
    }

    if let eventName = event.event {
      lines.append("event: \(eventName)")
    }

    let dataLines = splitDataLines(event.data)
    for line in dataLines {
      lines.append("data: \(line)")
    }

    if let retry = event.retry {
      lines.append("retry: \(retry)")
    }

    return lines.joined(separator: "\n")
  }

  private static func splitDataLines(_ data: String) -> [String] {
    if data.isEmpty {
      return [""]
    }

    return data
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
  }
}
