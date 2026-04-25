// By Dennis Müller

import SwiftAgent

extension AnthropicAdapter {
  func executeToolCall(
    _ toolCall: Transcript.ToolCall,
    generatedTranscript: inout Transcript,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) async throws {
    guard let tool = tools.first(where: { $0.name == toolCall.toolName }) else {
      AgentLog.error(
        GenerationError.unsupportedToolCalled(.init(toolName: toolCall.toolName)),
        context: "tool_not_found",
      )
      throw GenerationError.unsupportedToolCalled(.init(toolName: toolCall.toolName))
    }

    do {
      let output = try await callTool(tool, with: toolCall.arguments)
      appendToolOutput(
        toolName: tool.name,
        toolCall: toolCall,
        output: output.generatedContent,
        generatedTranscript: &generatedTranscript,
        continuation: continuation,
      )
    } catch let toolRunRejection as ToolRunRejection {
      appendToolOutput(
        toolName: tool.name,
        toolCall: toolCall,
        output: toolRunRejection.generatedContent,
        generatedTranscript: &generatedTranscript,
        continuation: continuation,
      )
    } catch {
      AgentLog.error(error, context: "tool_call_failed_\(tool.name)")
      throw GenerationError.toolExecutionFailed(toolName: tool.name, underlyingError: error)
    }
  }
}

private extension AnthropicAdapter {
  func callTool<T: SwiftAgent.Tool>(
    _ tool: T,
    with generatedContent: GeneratedContent,
  ) async throws -> T.Output where T.Output: ConvertibleToGeneratedContent {
    let arguments = try T.Arguments(generatedContent)
    return try await tool.call(arguments: arguments)
  }

  func appendToolOutput(
    toolName: String,
    toolCall: Transcript.ToolCall,
    output: GeneratedContent,
    generatedTranscript: inout Transcript,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) {
    let toolOutputEntry = Transcript.ToolOutput(
      id: toolCall.id,
      callId: toolCall.callId,
      toolName: toolCall.toolName,
      segment: .structure(
        Transcript.StructuredSegment(content: output),
      ),
      status: nil,
    )

    AgentLog.toolOutput(
      name: toolName,
      callId: toolCall.callId,
      outputJSONOrText: output.stableJsonString,
    )

    let transcriptEntry = Transcript.Entry.toolOutput(toolOutputEntry)
    generatedTranscript.entries.append(transcriptEntry)
    continuation.yield(.transcript(transcriptEntry))
  }
}
