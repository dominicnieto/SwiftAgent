import Foundation

/// A schema-specific grounding value decoded from prompt source data.
public protocol DecodedGrounding: Sendable, Equatable, Codable {}

/// A schema-specific structured output value decoded from transcript content.
public protocol DecodedStructuredOutput: Sendable, Equatable {
  /// Creates a placeholder for structured output that no registered decoder handles.
  static func makeUnknown(segment: Transcript.StructuredSegment) -> Self
}

/// A schema-specific tool run value decoded from transcript tool calls and outputs.
public protocol DecodedToolRun: Identifiable, Equatable, Sendable where ID == String {
  /// Stable identifier for the decoded tool run.
  var id: String { get }

  /// Creates a placeholder for a tool call that no registered decoder handles.
  static func makeUnknown(toolCall: Transcript.ToolCall) -> Self
}
