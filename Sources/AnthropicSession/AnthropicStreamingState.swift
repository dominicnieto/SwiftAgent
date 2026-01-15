// By Dennis Müller

import FoundationModels
import SwiftAgent

struct StreamingMessageState {
  var entryIndex: Int
  var responseId: String
  var status: SwiftAgent.Transcript.Status
  var structuredOutputTypeName: String?
  var structuredToolName: String?
  var structuredToolUseId: String?
  var structuredJSONBuffer: String
  var structuredContent: GeneratedContent?
  var textFragments: ContentFragmentBuffer

  init(
    entryIndex: Int,
    responseId: String,
    status: SwiftAgent.Transcript.Status,
    structuredOutputTypeName: String?,
    structuredToolName: String?,
  ) {
    self.entryIndex = entryIndex
    self.responseId = responseId
    self.status = status
    self.structuredOutputTypeName = structuredOutputTypeName
    self.structuredToolName = structuredToolName
    structuredToolUseId = nil
    structuredJSONBuffer = ""
    structuredContent = nil
    textFragments = ContentFragmentBuffer()
  }
}

struct StreamingReasoningState {
  var entryIndex: Int
  var summaryText: String
  var encryptedReasoning: String?
}

struct StreamingToolCallState {
  var toolUseId: String
  var toolName: String
  var argumentsBuffer: String
  var entryIndex: Int
  var hasInvokedTool: Bool

  init(
    toolUseId: String,
    toolName: String,
    entryIndex: Int,
  ) {
    self.toolUseId = toolUseId
    self.toolName = toolName
    argumentsBuffer = ""
    self.entryIndex = entryIndex
    hasInvokedTool = false
  }
}

struct ContentFragmentBuffer {
  private var fragments: [String] = []

  mutating func append(
    _ text: String,
    at index: Int,
  ) {
    ensureCapacity(for: index)
    fragments[index].append(text)
  }

  mutating func assign(
    _ text: String,
    at index: Int,
  ) {
    ensureCapacity(for: index)
    fragments[index] = text
  }

  func joined(
    separator: String = "",
  ) -> String {
    fragments.joined(separator: separator)
  }

  var nonEmptyFragments: [String] {
    fragments.filter { !$0.isEmpty }
  }

  private mutating func ensureCapacity(
    for index: Int,
  ) {
    if fragments.count <= index {
      fragments.append(contentsOf: Array(repeating: "", count: index - fragments.count + 1))
    }
  }
}
