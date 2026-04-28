// By Dennis Müller

import Foundation

/// A conversation transcript built by the agent.
///
/// The transcript is an ordered log of prompts, tool activity, and model
/// responses produced during a session. Use it to inspect streaming progress,
/// pretty‑print for debugging, or resolve provider‑specific structured output.
public struct Transcript: Sendable, Equatable, Codable {
  /// The ordered entries that make up the transcript. New entries are appended
  /// at the end as the session progresses.
  public var entries: [Entry]

  /// Creates a transcript, optionally seeded with existing entries.
  public init(entries: [Entry] = []) {
    self.entries = entries
  }

  /// Inserts the entry if it does not exist, or replaces the existing entry
  /// with the same `id`. Order is preserved when appending.
  package mutating func upsert(_ entry: Entry) {
    if let existingIndex = entries.firstIndex(where: { $0.id == entry.id }) {
      entries[existingIndex] = entry
    } else {
      entries.append(entry)
    }
  }

  /// Resolves this transcript using a ``SessionSchema``.
  ///
  /// - Parameters:
  ///   - schema: The session schema to use to resolve the transcript.
  /// - Returns: The resolved transcript.
  public func resolved<SessionSchema: TranscriptSchema>(
    using schema: SessionSchema,
  ) throws -> SessionSchema.Transcript {
    let resolver = TranscriptResolver(for: schema)
    return try resolver.resolve(self)
  }

  /// Returns the structured output and status from the most recent response
  /// when the session is configured for structured‑only output.
  ///
  /// - Returns: `nil` while streaming is in progress or when no response is
  ///   available.
  /// - Throws: A `GenerationError` if unexpected text or multiple structured
  ///   segments are present.
  package func lastResponseEntry() -> Response? {
    guard let lastEntry = entries.last else {
      return nil
    }
    guard case let .response(response) = lastEntry else {
      return nil
    }

    if response.segments.isEmpty {
      return nil
    }

    return response
  }
}

package extension Transcript {
  /// Convenience bundle containing the last response status and its single
  /// structured segment.
  struct LastResponseStructuredOutput: Sendable, Equatable {
    /// The completion status of the last response.
    var status: Transcript.Status
    /// The single structured segment produced by the last response.
    let segment: Transcript.StructuredSegment
  }
}

// MARK: - RandomAccessCollection Conformance

extension Transcript: RandomAccessCollection, RangeReplaceableCollection {
  public var startIndex: Int { entries.startIndex }
  public var endIndex: Int { entries.endIndex }

  public subscript(position: Int) -> Entry {
    entries[position]
  }

  public func index(after i: Int) -> Int {
    entries.index(after: i)
  }

  public func index(before i: Int) -> Int {
    entries.index(before: i)
  }

  public init() {
    entries = []
  }

  public mutating func replaceSubrange(_ subrange: Range<Int>, with newElements: some Collection<Entry>) {
    entries.replaceSubrange(subrange, with: newElements)
  }
}

public extension SwiftAgent.Transcript {
  /// A single unit in a transcript. Entries are identified by a stable `id`
  /// to support updates during streaming.
  enum Entry: Sendable, Identifiable, Equatable, Codable {
    /// Developer-provided instructions that define model behavior for the session.
    case instructions(Instructions)
    /// The final rendered prompt that was sent to the model.
    case prompt(Prompt)
    /// A summarized reasoning trace, if provided by the model.
    case reasoning(Reasoning)
    /// One or more tool invocations emitted by the model.
    case toolCalls(ToolCalls)
    /// Output emitted by a tool in response to a prior tool call.
    case toolOutput(ToolOutput)
    /// The model's response for the turn.
    case response(Response)

    /// Stable identifier for this entry.
    public var id: String {
      switch self {
      case let .instructions(instructions):
        instructions.id
      case let .prompt(prompt):
        prompt.id
      case let .reasoning(reasoning):
        reasoning.id
      case let .toolCalls(toolCalls):
        toolCalls.id
      case let .toolOutput(toolOutput):
        toolOutput.id
      case let .response(response):
        response.id
      }
    }
  }

  /// Developer-provided instructions and tool definitions available to the model.
  struct Instructions: Sendable, Identifiable, Equatable, Codable {
    /// Identifier for this instructions entry.
    public var id: String
    /// Ordered instruction content segments.
    public var segments: [Segment]
    /// Tool definitions injected into the instruction context.
    public var toolDefinitions: [ToolDefinition]

    public init(
      id: String = UUID().uuidString,
      segments: [Segment],
      toolDefinitions: [ToolDefinition] = [],
    ) {
      self.id = id
      self.segments = segments
      self.toolDefinitions = toolDefinitions
    }
  }

  /// A model-visible tool definition included with session instructions.
  struct ToolDefinition: Sendable, Identifiable, Equatable, Codable {
    /// Stable identifier derived from the tool name.
    public var id: String { name }
    /// Tool name exposed to the model.
    public var name: String
    /// Natural-language description of the tool.
    public var description: String
    /// Schema for tool arguments.
    public var parameters: GenerationSchema

    public init(name: String, description: String, parameters: GenerationSchema) {
      self.name = name
      self.description = description
      self.parameters = parameters
    }

    public init(tool: any Tool) {
      self.init(
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters,
      )
    }
  }

  /// The final rendered prompt that was sent to the model, alongside the
  /// original input and prompt sources used to construct it.
  struct Prompt: Sendable, Identifiable, Equatable, Codable {
    /// Identifier for this prompt instance.
    public var id: String
    /// The user's raw input used to build the prompt.
    public var input: String
    /// Opaque data describing prompt sources used to reproduce the prompt.
    public var sources: Data
    /// The full rendered prompt string sent to the model.
    package var prompt: String
    private var storedSegments: [Segment]?

    package init(
      id: String = UUID().uuidString,
      input: String,
      sources: Data,
      prompt: String,
      segments: [Segment]? = nil,
    ) {
      self.id = id
      self.input = input
      self.sources = sources
      self.prompt = prompt
      storedSegments = segments
    }

    /// Prompt content represented as transcript segments for provider request builders.
    public var segments: [Segment] {
      storedSegments ?? [.text(.init(content: prompt))]
    }
  }

  /// A lightweight summary of the model's private reasoning, when available.
  struct Reasoning: Sendable, Identifiable, Equatable, Codable {
    /// Identifier for this reasoning instance.
    public var id: String
    /// High‑level reasoning summary lines.
    public var summary: [String]
    /// Provider‑specific encrypted reasoning payload, if present.
    public var encryptedReasoning: String?
    /// The status of the reasoning step, if reported.
    public var status: Status?

    package init(
      id: String,
      summary: [String],
      encryptedReasoning: String?,
      status: Status? = nil,
    ) {
      self.id = id
      self.summary = summary
      self.encryptedReasoning = encryptedReasoning
      self.status = status
    }
  }

  /// The lifecycle state of a response or step.
  enum Status: Sendable, Identifiable, Equatable, Codable {
    /// The operation finished successfully.
    case completed
    /// The operation ended before completion.
    case incomplete
    /// The operation is still in progress.
    case inProgress

    /// Identifiable conformance uses the case value itself.
    public var id: Self { self }
  }

  /// A collection of tool calls emitted in a single turn.
  struct ToolCalls: Sendable, Identifiable, Equatable, Codable {
    /// Identifier for this group of tool calls.
    public var id: String
    /// The ordered tool calls.
    public var calls: [ToolCall]

    public init(id: String = UUID().uuidString, calls: [ToolCall]) {
      self.id = id
      self.calls = calls
    }
  }
}

// MARK: - ToolCalls RandomAccessCollection Conformance

extension Transcript.ToolCalls: RandomAccessCollection, RangeReplaceableCollection {
  public var startIndex: Int { calls.startIndex }
  public var endIndex: Int { calls.endIndex }

  public subscript(position: Int) -> Transcript.ToolCall {
    calls[position]
  }

  public func index(after i: Int) -> Int {
    calls.index(after: i)
  }

  public func index(before i: Int) -> Int {
    calls.index(before: i)
  }

  public init() {
    id = UUID().uuidString
    calls = []
  }

  public mutating func replaceSubrange(
    _ subrange: Range<Int>,
    with newElements: some Collection<Transcript.ToolCall>,
  ) {
    calls.replaceSubrange(subrange, with: newElements)
  }
}

public extension Transcript {
  /// A single tool invocation requested by the model.
  struct ToolCall: Sendable, Identifiable, Equatable, Codable {
    /// Identifier for this tool call record.
    public var id: String
    /// Correlation identifier supplied by the model.
    public var callId: String
    /// The tool's canonical name.
    public var toolName: String
    /// JSON arguments for the tool call.
    public var arguments: GeneratedContent
    /// Raw partial JSON arguments while a streaming provider is still emitting the tool input.
    public var partialArguments: String?
    /// Optional status of the tool call as it progresses.
    public var status: Status?

    public init(
      id: String,
      callId: String,
      toolName: String,
      arguments: GeneratedContent,
      partialArguments: String? = nil,
      status: Status?,
    ) {
      self.id = id
      self.callId = callId
      self.toolName = toolName
      self.arguments = arguments
      self.partialArguments = partialArguments
      self.status = status
    }

    /// Creates a completed tool call when the provider uses one identifier for both local and provider correlation.
    public init(
      id: String,
      toolName: String,
      arguments: GeneratedContent,
    ) {
      self.init(
        id: id,
        callId: id,
        toolName: toolName,
        arguments: arguments,
        partialArguments: nil,
        status: .completed,
      )
    }
  }

  /// Output produced by a tool in response to a call.
  struct ToolOutput: Sendable, Identifiable, Equatable, Codable {
    /// Identifier for this tool output record.
    public var id: String
    /// Correlation identifier matching the originating tool call.
    public var callId: String
    /// The tool's canonical name.
    public var toolName: String
    /// The tool output as a segment (text or structured).
    public var segment: Segment
    /// Optional status reflecting the processing state.
    public var status: Status?

    public init(
      id: String,
      callId: String,
      toolName: String,
      segment: Segment,
      status: Status?,
    ) {
      self.id = id
      self.callId = callId
      self.toolName = toolName
      self.segment = segment
      self.status = status
    }

    /// Creates a completed tool output using the first segment from a provider-produced segment list.
    public init(
      id: String,
      toolName: String,
      segments: [Segment],
    ) {
      self.init(
        id: id,
        callId: id,
        toolName: toolName,
        segment: segments.first ?? .text(.init(content: "")),
        status: .completed,
      )
    }

    /// Single-element segment list for provider code that handles multi-segment outputs.
    public var segments: [Segment] {
      [segment]
    }
  }

  /// The model's response for a single turn.
  struct Response: Sendable, Identifiable, Equatable, Codable {
    /// Identifier for this response.
    public var id: String
    /// Ordered response segments (text and/or structured).
    public var segments: [Segment]
    /// Whether the response completed or is still in progress.
    public var status: Status

    public init(
      id: String,
      segments: [Segment],
      status: Status,
    ) {
      self.id = id
      self.segments = segments
      self.status = status
    }

    /// Creates a completed response from provider-produced segments.
    public init(
      assetIDs: [String] = [],
      segments: [Segment],
    ) {
      _ = assetIDs
      self.init(id: UUID().uuidString, segments: segments, status: .completed)
    }

    /// All text segments in order.
    public var textSegments: [TextSegment] {
      segments.compactMap { segment in
        switch segment {
        case let .text(textSegment):
          textSegment
        case .structure, .image:
          nil
        }
      }
    }

    /// All structured segments in order.
    public var structuredSegments: [StructuredSegment] {
      segments.compactMap { segment in
        switch segment {
        case let .structure(structuredSegment):
          structuredSegment
        case .text, .image:
          nil
        }
      }
    }

    /// Convenience joined text from all text segments, or `nil` when none.
    public var text: String? {
      let contents = textSegments.map(\.content)
      if contents.isEmpty { return nil }
      return contents.joined(separator: "\n")
    }
  }

  /// A response or tool output segment.
  enum Segment: Sendable, Identifiable, Equatable, Codable {
    /// A unit of plain text.
    case text(TextSegment)
    /// A unit of structured content.
    case structure(StructuredSegment)
    /// A unit of image content.
    case image(ImageSegment)

    /// Stable identifier for the underlying segment.
    public var id: String {
      switch self {
      case let .text(textSegment):
        textSegment.id
      case let .structure(structuredSegment):
        structuredSegment.id
      case let .image(imageSegment):
        imageSegment.id
      }
    }
  }

  /// A unit of plain text produced by the model or a tool.
  struct TextSegment: Sendable, Identifiable, Equatable, Codable {
    /// Identifier for this segment.
    public var id: String
    /// The textual content.
    public var content: String

    public init(id: String = UUID().uuidString, content: String) {
      self.id = id
      self.content = content
    }
  }

  /// A unit of structured content produced by the model or a tool.
  struct StructuredSegment: Sendable, Identifiable, Equatable, Codable {
    /// Identifier for this segment.
    public var id: String
    /// Optional type hint for the structured payload.
    public var typeName: String
    /// The structured payload as generated content.
    public var content: GeneratedContent

    public init(id: String = UUID().uuidString, typeName: String = "", content: GeneratedContent) {
      self.id = id
      self.typeName = typeName
      self.content = content
    }

    public init(id: String = UUID().uuidString, typeName: String = "", content: some ConvertibleToGeneratedContent) {
      self.id = id
      self.typeName = typeName
      self.content = content.generatedContent
    }
  }

  /// A unit of image content used for multimodal prompts and responses.
  struct ImageSegment: Sendable, Identifiable, Equatable, Codable {
    /// Identifier for this segment.
    public var id: String
    /// The source of the image data.
    public var source: Source

    /// The origin of image content.
    public enum Source: Sendable, Equatable, Codable {
      /// Encoded image bytes and their MIME type.
      case data(Data, mimeType: String)
      /// A URL that references an image.
      case url(URL)

      private enum CodingKeys: String, CodingKey {
        case kind
        case data
        case mimeType
        case url
      }

      public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "data":
          let data = try container.decode(Data.self, forKey: .data)
          let mimeType = try container.decode(String.self, forKey: .mimeType)
          self = .data(data, mimeType: mimeType)
        case "url":
          self = .url(try container.decode(URL.self, forKey: .url))
        default:
          throw DecodingError.dataCorruptedError(
            forKey: .kind,
            in: container,
            debugDescription: "Unknown image source kind: \(kind)",
          )
        }
      }

      public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .data(data, mimeType):
          try container.encode("data", forKey: .kind)
          try container.encode(data, forKey: .data)
          try container.encode(mimeType, forKey: .mimeType)
        case let .url(url):
          try container.encode("url", forKey: .kind)
          try container.encode(url, forKey: .url)
        }
      }
    }

    public init(id: String = UUID().uuidString, source: Source) {
      self.id = id
      self.source = source
    }

    public init(id: String = UUID().uuidString, data: Data, mimeType: String) {
      self.id = id
      source = .data(data, mimeType: mimeType)
    }

    public init(id: String = UUID().uuidString, url: URL) {
      self.id = id
      source = .url(url)
    }
  }
}

// MARK: - Transcript Codable Support

public extension Transcript.ToolCall {
  private enum CodingKeys: String, CodingKey {
    case id
    case callId
    case toolName
    case arguments
    case partialArguments
    case status
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(String.self, forKey: .id)
    callId = try container.decode(String.self, forKey: .callId)
    toolName = try container.decode(String.self, forKey: .toolName)
    let argumentsJSONString = try container.decode(String.self, forKey: .arguments)
    partialArguments = try container.decodeIfPresent(String.self, forKey: .partialArguments)

    do {
      arguments = try GeneratedContent(json: argumentsJSONString)
    } catch {
      let description = "Failed to decode GeneratedContent from arguments JSON string: \(error)"
      throw DecodingError.dataCorruptedError(forKey: .arguments, in: container, debugDescription: description)
    }

    status = try container.decodeIfPresent(Transcript.Status.self, forKey: .status)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(id, forKey: .id)
    try container.encode(callId, forKey: .callId)
    try container.encode(toolName, forKey: .toolName)
    try container.encode(arguments.stableJsonString, forKey: .arguments)
    try container.encodeIfPresent(partialArguments, forKey: .partialArguments)
    try container.encodeIfPresent(status, forKey: .status)
  }
}

public extension Transcript.StructuredSegment {
  private enum CodingKeys: String, CodingKey {
    case id
    case typeName
    case content
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(String.self, forKey: .id)
    typeName = try container.decodeIfPresent(String.self, forKey: .typeName) ?? ""
    let contentJSONString = try container.decode(String.self, forKey: .content)

    do {
      content = try GeneratedContent(json: contentJSONString)
    } catch {
      let description = "Failed to decode GeneratedContent from content JSON string: \(error)"
      throw DecodingError.dataCorruptedError(forKey: .content, in: container, debugDescription: description)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(id, forKey: .id)
    try container.encode(typeName, forKey: .typeName)
    try container.encode(content.stableJsonString, forKey: .content)
  }
}

// MARK: - Pretty Printing

public extension Transcript {
  func prettyPrintedDescription(indentedBy indentationLevel: Int = 0) -> String {
    prettyPrintedLines(indentedBy: indentationLevel).joined(separator: "\n")
  }
}

extension Transcript: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    prettyPrintedDescription()
  }

  public var debugDescription: String {
    prettyPrintedDescription()
  }
}

private extension Transcript {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)Transcript [")
    if entries.isEmpty {
      let childIndentation = transcriptIndentation(for: indentationLevel + 1)
      lines.append("\(childIndentation)<empty>")
    } else {
      for entry in entries {
        lines.append(contentsOf: entry.prettyPrintedLines(indentedBy: indentationLevel + 1))
      }
    }
    lines.append("\(currentIndentation)]")
    return lines
  }
}

private extension Transcript.Entry {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    switch self {
    case let .instructions(instructions):
      instructions.prettyPrintedLines(indentedBy: indentationLevel)
    case let .prompt(prompt):
      prompt.prettyPrintedLines(indentedBy: indentationLevel, headline: "Prompt")
    case let .reasoning(reasoning):
      reasoning.prettyPrintedLines(indentedBy: indentationLevel)
    case let .toolCalls(toolCalls):
      toolCalls.prettyPrintedLines(indentedBy: indentationLevel)
    case let .toolOutput(toolOutput):
      toolOutput.prettyPrintedLines(indentedBy: indentationLevel)
    case let .response(response):
      response.prettyPrintedLines(indentedBy: indentationLevel)
    }
  }
}

private extension Transcript.Instructions {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)Instructions(id: \(id)) {")
    lines.append(contentsOf: transcriptPrettyCollection(
      name: "segments",
      indentationLevel: indentationLevel + 1,
      elements: segments,
      renderElement: { segment, elementIndentationLevel in
        segment.prettyPrintedLines(indentedBy: elementIndentationLevel)
      },
    ))
    lines.append(contentsOf: transcriptPrettyCollection(
      name: "toolDefinitions",
      indentationLevel: indentationLevel + 1,
      elements: toolDefinitions,
      renderElement: { definition, elementIndentationLevel in
        definition.prettyPrintedLines(indentedBy: elementIndentationLevel)
      },
    ))
    lines.append("\(currentIndentation)}")
    return lines
  }
}

private extension Transcript.ToolDefinition {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)ToolDefinition(id: \(id)) {")
    lines.append(contentsOf: transcriptPrettyField(
      name: "name",
      value: name,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append(contentsOf: transcriptPrettyField(
      name: "description",
      value: description,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append("\(currentIndentation)}")
    return lines
  }
}

private extension Transcript.Prompt {
  func prettyPrintedLines(indentedBy indentationLevel: Int, headline: String) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)\(headline)(id: \(id)) {")
    lines.append(contentsOf: transcriptPrettyField(name: "input", value: input, indentationLevel: indentationLevel + 1))
    lines.append(contentsOf: transcriptPrettyField(
      name: "prompt",
      value: prompt,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append("\(currentIndentation)}")
    return lines
  }
}

private extension Transcript.Reasoning {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)Reasoning(id: \(id)) {")
    lines.append(contentsOf: transcriptPrettyStringCollection(
      name: "summary",
      values: summary,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append(contentsOf: transcriptPrettyOptionalField(
      name: "encryptedReasoning",
      value: encryptedReasoning,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append(contentsOf: transcriptPrettyOptionalField(
      name: "status",
      value: status.map { String(describing: $0) },
      indentationLevel: indentationLevel + 1,
    ))
    lines.append("\(currentIndentation)}")
    return lines
  }
}

private extension Transcript.ToolCalls {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)ToolCalls(id: \(id)) {")
    lines.append(contentsOf: transcriptPrettyCollection(
      name: "calls",
      indentationLevel: indentationLevel + 1,
      elements: calls,
      renderElement: { call, elementIndentationLevel in
        call.prettyPrintedLines(indentedBy: elementIndentationLevel)
      },
    ))
    lines.append("\(currentIndentation)}")
    return lines
  }
}

private extension Transcript.ToolCall {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)ToolCall(id: \(id)) {")
    lines.append(contentsOf: transcriptPrettyField(
      name: "callId",
      value: callId,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append(contentsOf: transcriptPrettyField(
      name: "toolName",
      value: toolName,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append(contentsOf: transcriptPrettyValue(
      value: transcriptPrettyJSONString(from: arguments),
      indentationLevel: indentationLevel + 1,
      name: "arguments",
    ))
    lines.append(contentsOf: transcriptPrettyOptionalField(
      name: "partialArguments",
      value: partialArguments,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append(contentsOf: transcriptPrettyOptionalField(
      name: "status",
      value: status.map { String(describing: $0) },
      indentationLevel: indentationLevel + 1,
    ))
    lines.append("\(currentIndentation)}")
    return lines
  }
}

private extension Transcript.ToolOutput {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)ToolOutput(id: \(id)) {")
    lines.append(contentsOf: transcriptPrettyField(
      name: "callId",
      value: callId,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append(contentsOf: transcriptPrettyField(
      name: "toolName",
      value: toolName,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append(contentsOf: transcriptPrettyOptionalField(
      name: "status",
      value: status.map { String(describing: $0) },
      indentationLevel: indentationLevel + 1,
    ))
    lines.append(contentsOf: transcriptPrettyCollection(
      name: "segment",
      indentationLevel: indentationLevel + 1,
      elements: [segment],
      renderElement: { segment, elementIndentationLevel in
        segment.prettyPrintedLines(indentedBy: elementIndentationLevel)
      },
    ))
    lines.append("\(currentIndentation)}")
    return lines
  }
}

private extension Transcript.Response {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)Response(id: \(id)) {")
    lines.append(contentsOf: transcriptPrettyField(
      name: "status",
      value: String(describing: status),
      indentationLevel: indentationLevel + 1,
    ))
    lines.append(contentsOf: transcriptPrettyCollection(
      name: "segments",
      indentationLevel: indentationLevel + 1,
      elements: segments,
      renderElement: { segment, elementIndentationLevel in
        segment.prettyPrintedLines(indentedBy: elementIndentationLevel)
      },
    ))
    lines.append("\(currentIndentation)}")
    return lines
  }
}

private extension Transcript.Segment {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    switch self {
    case let .text(textSegment):
      textSegment.prettyPrintedLines(indentedBy: indentationLevel)
    case let .structure(structuredSegment):
      structuredSegment.prettyPrintedLines(indentedBy: indentationLevel)
    case let .image(imageSegment):
      imageSegment.prettyPrintedLines(indentedBy: indentationLevel)
    }
  }
}

private extension Transcript.TextSegment {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)TextSegment(id: \(id)) {")
    lines.append(contentsOf: transcriptPrettyField(
      name: "content",
      value: content,
      indentationLevel: indentationLevel + 1,
    ))
    lines.append("\(currentIndentation)}")
    return lines
  }
}

private extension Transcript.StructuredSegment {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)StructuredSegment(id: \(id)) {")
    lines.append(contentsOf: transcriptPrettyValue(
      value: transcriptPrettyJSONString(from: content),
      indentationLevel: indentationLevel + 1,
      name: "content",
    ))
    lines.append("\(currentIndentation)}")
    return lines
  }
}

private extension Transcript.ImageSegment {
  func prettyPrintedLines(indentedBy indentationLevel: Int) -> [String] {
    var lines: [String] = []
    let currentIndentation = transcriptIndentation(for: indentationLevel)
    lines.append("\(currentIndentation)ImageSegment(id: \(id)) {")
    switch source {
    case let .data(data, mimeType):
      lines.append(contentsOf: transcriptPrettyField(
        name: "source",
        value: "data(\(mimeType), \(data.count) bytes)",
        indentationLevel: indentationLevel + 1,
      ))
    case let .url(url):
      lines.append(contentsOf: transcriptPrettyField(
        name: "source",
        value: url.absoluteString,
        indentationLevel: indentationLevel + 1,
      ))
    }
    lines.append("\(currentIndentation)}")
    return lines
  }
}

// MARK: - Pretty Printing Helpers

private func transcriptIndentation(for indentationLevel: Int) -> String {
  String(repeating: "  ", count: indentationLevel)
}

private func transcriptPrettyField(name: String, value: String, indentationLevel: Int) -> [String] {
  transcriptPrettyValue(value: value, indentationLevel: indentationLevel, name: name)
}

private func transcriptPrettyOptionalField(name: String, value: String?, indentationLevel: Int) -> [String] {
  guard let value else { return [] }

  return transcriptPrettyField(name: name, value: value, indentationLevel: indentationLevel)
}

private func transcriptPrettyStringCollection(
  name: String,
  values: [String],
  indentationLevel: Int,
) -> [String] {
  let indentation = transcriptIndentation(for: indentationLevel)
  guard !values.isEmpty else {
    return ["\(indentation)\(name): []"]
  }

  var lines = ["\(indentation)\(name): ["]
  for value in values {
    lines.append(contentsOf: transcriptPrettyValue(
      value: value,
      indentationLevel: indentationLevel + 1,
      bullet: "- ",
    ))
  }
  lines.append("\(indentation)]")
  return lines
}

private func transcriptPrettyCollection<Element>(
  name: String,
  indentationLevel: Int,
  elements: [Element],
  renderElement: (Element, Int) -> [String],
) -> [String] {
  let indentation = transcriptIndentation(for: indentationLevel)
  guard !elements.isEmpty else {
    return ["\(indentation)\(name): []"]
  }

  var lines = ["\(indentation)\(name): ["]
  for element in elements {
    lines.append(contentsOf: renderElement(element, indentationLevel + 1))
  }
  lines.append("\(indentation)]")
  return lines
}

private func transcriptPrettyValue(
  value: String,
  indentationLevel: Int,
  name: String? = nil,
  bullet: String? = nil,
) -> [String] {
  let indentation = transcriptIndentation(for: indentationLevel)
  let rawLines = value.components(separatedBy: "\n")
  let valueLines: [String] = if rawLines.count == 1, rawLines.first?.isEmpty == true {
    ["<empty>"]
  } else {
    rawLines
  }

  if let name {
    guard let firstLine = valueLines.first else {
      return ["\(indentation)\(name):"]
    }

    if valueLines.count == 1 {
      return ["\(indentation)\(name): \(firstLine)"]
    }
    var lines = ["\(indentation)\(name):"]
    let nestedIndentation = transcriptIndentation(for: indentationLevel + 1)
    for line in valueLines {
      lines.append("\(nestedIndentation)\(line)")
    }
    return lines
  }

  if let bullet {
    var lines: [String] = []
    let bulletIndentation = transcriptIndentation(for: indentationLevel)
    for (index, line) in valueLines.enumerated() {
      if index == 0 {
        lines.append("\(bulletIndentation)\(bullet)\(line)")
      } else {
        let nestedIndentation = transcriptIndentation(for: indentationLevel + 1)
        lines.append("\(nestedIndentation)\(line)")
      }
    }
    return lines
  }

  return valueLines.map { "\(indentation)\($0)" }
}

private func transcriptPrettyJSONString(from generatedContent: GeneratedContent) -> String {
  let rawJSONString = generatedContent.stableJsonString
  guard let data = rawJSONString.data(using: .utf8) else {
    return rawJSONString
  }
  guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
    return rawJSONString
  }
  guard JSONSerialization.isValidJSONObject(jsonObject) else {
    return rawJSONString
  }
  guard let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys, .prettyPrinted])
  else {
    return rawJSONString
  }

  return String(decoding: prettyData, as: UTF8.self)
}
