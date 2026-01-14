// By Dennis Müller

import Foundation
import FoundationModels
import SwiftAgent
@preconcurrency import SwiftAnthropic

public actor AnthropicAdapter: Adapter {
  public typealias Model = AnthropicModel
  public typealias Transcript = SwiftAgent.Transcript
  public typealias ConfigurationError = AnthropicGenerationOptionsError

  public nonisolated let tools: [any SwiftAgentTool]
  package let instructions: String
  package let httpClient: SwiftAgent.HTTPClient
  package let messagesPath: String = "/v1/messages"

  public init(
    tools: [any SwiftAgentTool],
    instructions: String,
    configuration: AnthropicConfiguration,
  ) {
    self.tools = tools
    self.instructions = instructions
    httpClient = configuration.httpClient
  }

  public func respond(
    to prompt: Transcript.Prompt,
    generating type: (some StructuredOutput).Type?,
    using model: Model = .default,
    including transcript: Transcript,
    options: AnthropicGenerationOptions,
  ) -> AsyncThrowingStream<AdapterUpdate, any Error> {
    let setup = AsyncThrowingStream<AdapterUpdate, any Error>.makeStream()

    AgentLog.start(
      model: String(describing: model),
      toolNames: tools.map(\.name),
      promptPreview: prompt.input,
    )

    let task = Task<Void, Never> {
      do {
        try options.validate(for: model)
      } catch {
        AgentLog.error(error, context: "Invalid generation options")
        setup.continuation.finish(throwing: error)
        return
      }

      do {
        try await run(
          transcript: transcript,
          generating: type,
          using: model,
          options: options,
          continuation: setup.continuation,
        )
      } catch {
        AgentLog.error(error, context: "agent response")
        setup.continuation.finish(throwing: error)
        return
      }

      setup.continuation.finish()
    }

    setup.continuation.onTermination = { _ in
      task.cancel()
    }

    return setup.stream
  }

  private func run(
    transcript: Transcript,
    generating type: (some StructuredOutput).Type?,
    using model: Model = .default,
    options: AnthropicGenerationOptions,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) async throws {
    var generatedTranscript = Transcript()
    let allowedSteps = 20
    var currentStep = 0

    for _ in 0..<allowedSteps {
      try Task.checkCancellation()
      currentStep += 1
      AgentLog.stepRequest(step: currentStep)

      let request = try messageRequest(
        including: Transcript(entries: transcript.entries + generatedTranscript.entries),
        generating: type,
        using: model,
        options: options,
        streamResponses: false,
      )

      try Task.checkCancellation()

      let response: MessageResponse
      do {
        response = try await httpClient.send(
          path: messagesPath,
          method: .post,
          queryItems: nil,
          headers: nil,
          body: request,
          responseType: MessageResponse.self,
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw GenerationError.fromRequest(error, httpErrorMapper: GenerationError.from)
      }

      if let usage = tokenUsage(from: response) {
        AgentLog.tokenUsage(
          inputTokens: usage.inputTokens,
          outputTokens: usage.outputTokens,
          totalTokens: usage.totalTokens,
          cachedTokens: usage.cachedTokens,
          reasoningTokens: usage.reasoningTokens,
        )
        continuation.yield(.tokenUsage(usage))
      }

      let toolCalls = try handleResponse(
        response,
        generating: type,
        generatedTranscript: &generatedTranscript,
        continuation: continuation,
      )

      if toolCalls.isEmpty {
        AgentLog.finish()
        continuation.finish()
        return
      }

      for toolCall in toolCalls {
        try Task.checkCancellation()
        try await executeToolCall(
          toolCall,
          generatedTranscript: &generatedTranscript,
          continuation: continuation,
        )
      }
    }
  }

  private func handleResponse(
    _ response: MessageResponse,
    generating type: (some StructuredOutput).Type?,
    generatedTranscript: inout Transcript,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) throws -> [Transcript.ToolCall] {
    let structuredOutputTypeName = type?.name
    let structuredToolName = try structuredOutputToolName(for: structuredOutputTypeName)

    var textFragments: [String] = []
    var toolCalls: [Transcript.ToolCall] = []
    var structuredContent: GeneratedContent?

    var reasoningSummary: [String] = []
    var encryptedReasoning: String?

    let status = transcriptStatus(from: response.stopReason)

    for content in response.content {
      switch content {
      case let .text(text, _):
        textFragments.append(text)

      case let .toolUse(toolUse):
        if let structuredToolName, toolUse.name == structuredToolName {
          structuredContent = try AnthropicMessageBuilder.generatedContent(from: toolUse.input)
        } else {
          let arguments = try AnthropicMessageBuilder.generatedContent(from: toolUse.input)
          let toolCall = Transcript.ToolCall(
            id: toolUse.id,
            callId: toolUse.id,
            toolName: toolUse.name,
            arguments: arguments,
            status: .completed,
          )
          toolCalls.append(toolCall)
        }

      case let .thinking(thinking):
        if !thinking.thinking.isEmpty {
          reasoningSummary.append(thinking.thinking)
        }
        if let signature = thinking.signature {
          encryptedReasoning = signature
        }

      default:
        break
      }
    }

    if !reasoningSummary.isEmpty || encryptedReasoning != nil {
      let reasoningEntry = Transcript.Reasoning(
        id: UUID().uuidString,
        summary: reasoningSummary,
        encryptedReasoning: encryptedReasoning,
        status: status,
      )
      AgentLog.reasoning(summary: reasoningSummary)
      let entry = Transcript.Entry.reasoning(reasoningEntry)
      generatedTranscript.entries.append(entry)
      continuation.yield(.transcript(entry))
    }

    if let structuredContent {
      if !textFragments.isEmpty {
        throw GenerationError.unexpectedTextResponse(.init())
      }

      guard let structuredOutputTypeName else {
        throw GenerationError.unexpectedStructuredResponse(.init())
      }

      let responseEntry = Transcript.Response(
        id: response.id ?? UUID().uuidString,
        segments: [
          .structure(
            Transcript.StructuredSegment(
              typeName: structuredOutputTypeName,
              content: structuredContent,
            ),
          ),
        ],
        status: status,
      )

      AgentLog.outputStructured(
        json: structuredContent.stableJsonString,
        status: response.stopReason ?? "completed",
      )

      generatedTranscript.entries.append(.response(responseEntry))
      continuation.yield(.transcript(.response(responseEntry)))

      return []
    }

    if let structuredOutputTypeName, structuredContent == nil {
      _ = structuredOutputTypeName
      throw GenerationError.unexpectedStructuredResponse(.init())
    }

    if !textFragments.isEmpty {
      let responseEntry = Transcript.Response(
        id: response.id ?? UUID().uuidString,
        segments: textFragments.map { .text(.init(content: $0)) },
        status: status,
      )

      let combined = textFragments.joined(separator: "\n")
      AgentLog.outputMessage(
        text: combined,
        status: response.stopReason ?? "completed",
      )

      generatedTranscript.entries.append(.response(responseEntry))
      continuation.yield(.transcript(.response(responseEntry)))
    } else if toolCalls.isEmpty {
      throw GenerationError.emptyMessageContent(.init(expectedType: structuredOutputTypeName ?? "String"))
    }

    if !toolCalls.isEmpty {
      let entry = Transcript.ToolCalls(calls: toolCalls)
      AgentLog.toolCall(
        name: toolCalls.map(\.toolName).joined(separator: ","),
        callId: toolCalls.map(\.callId).joined(separator: ","),
        argumentsJSON: toolCalls.map(\.arguments.stableJsonString).joined(separator: "\n"),
      )
      generatedTranscript.entries.append(.toolCalls(entry))
      continuation.yield(.transcript(.toolCalls(entry)))
    }

    return toolCalls
  }

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
        name: tool.name,
        callId: toolCall.callId,
        outputJSONOrText: output.generatedContent.stableJsonString,
      )

      let transcriptEntry = Transcript.Entry.toolOutput(toolOutputEntry)
      generatedTranscript.entries.append(transcriptEntry)
      continuation.yield(.transcript(transcriptEntry))
    } catch let toolRunRejection as ToolRunRejection {
      let toolOutputEntry = Transcript.ToolOutput(
        id: toolCall.id,
        callId: toolCall.callId,
        toolName: toolCall.toolName,
        segment: .structure(
          Transcript.StructuredSegment(content: toolRunRejection.generatedContent),
        ),
        status: nil,
      )

      AgentLog.toolOutput(
        name: tool.name,
        callId: toolCall.callId,
        outputJSONOrText: toolRunRejection.generatedContent.stableJsonString,
      )

      let transcriptEntry = Transcript.Entry.toolOutput(toolOutputEntry)
      generatedTranscript.entries.append(transcriptEntry)
      continuation.yield(.transcript(transcriptEntry))
    } catch {
      AgentLog.error(error, context: "tool_call_failed_\(tool.name)")
      throw GenerationError.toolExecutionFailed(toolName: tool.name, underlyingError: error)
    }
  }

  func messageRequest(
    including transcript: Transcript,
    generating type: (some StructuredOutput).Type?,
    using model: Model,
    options: AnthropicGenerationOptions,
    streamResponses: Bool,
  ) throws -> MessageParameter {
    let messages = try AnthropicMessageBuilder.messages(
      from: transcript,
      includeThinking: options.thinking != nil,
    )

    let systemPrompt: MessageParameter.System? = instructions.isEmpty
      ? nil
      : .text(instructions)

    let toolChoice = try resolvedToolChoice(
      for: type,
      options: options,
    )

    let tools = try resolvedTools(
      for: type,
    )

    return MessageParameter(
      model: .other(model.rawValue),
      messages: messages,
      maxTokens: options.maxOutputTokens ?? 1024,
      system: systemPrompt,
      metadata: nil,
      stopSequences: options.stopSequences,
      stream: streamResponses,
      temperature: options.temperature,
      topK: options.topK,
      topP: options.topP,
      tools: tools,
      toolChoice: toolChoice,
      thinking: options.thinking,
      container: nil,
    )
  }

  private func resolvedToolChoice(
    for type: (some StructuredOutput).Type?,
    options: AnthropicGenerationOptions,
  ) throws -> MessageParameter.ToolChoice? {
    if let type {
      guard let name = try structuredOutputToolName(for: type.name) else {
        throw GenerationError.requestFailed(
          reason: .invalidRequestConfiguration,
          detail: "Structured output requires a tool name.",
        )
      }

      return MessageParameter.ToolChoice(
        type: .tool,
        name: name,
        disableParallelToolUse: true,
      )
    }

    return options.toolChoice
  }

  private func resolvedTools(
    for type: (some StructuredOutput).Type?,
  ) throws -> [MessageParameter.Tool]? {
    var resolved: [MessageParameter.Tool] = try tools.map { tool in
      try .function(
        name: tool.name,
        description: tool.description,
        inputSchema: tool.parameters.asAnthropicJSONSchema(),
        cacheControl: nil,
      )
    }

    if let type {
      guard let name = try structuredOutputToolName(for: type.name) else {
        throw GenerationError.requestFailed(
          reason: .invalidRequestConfiguration,
          detail: "Structured output requires a tool name.",
        )
      }

      let schema = type.Schema.generationSchema
      let jsonSchema = try schema.asAnthropicJSONSchema()

      resolved.append(
        .function(
          name: name,
          description: "SwiftAgent structured output: \(type.name)",
          inputSchema: jsonSchema,
          cacheControl: nil,
        ),
      )
    }

    return resolved.isEmpty ? nil : resolved
  }

  func structuredOutputToolName(
    for typeName: String?,
  ) throws -> String? {
    guard let typeName else {
      return nil
    }

    let baseName = "swiftagent_structured_output"

    if tools.contains(where: { $0.name == baseName }) {
      throw GenerationError.requestFailed(
        reason: .invalidRequestConfiguration,
        detail: "Tool name conflict with reserved tool \"\(baseName)\".",
      )
    }

    _ = typeName
    return baseName
  }

  func transcriptStatus(
    from stopReason: String?,
  ) -> Transcript.Status {
    switch stopReason {
    case "max_tokens":
      .incomplete
    default:
      .completed
    }
  }

  func tokenUsage(
    from response: MessageResponse,
  ) -> TokenUsage? {
    tokenUsage(from: response.usage)
  }

  func tokenUsage(
    from usage: MessageResponse.Usage,
  ) -> TokenUsage? {
    let inputTokens = usage.inputTokens
    let outputTokens = usage.outputTokens
    let totalTokens = inputTokens.map { $0 + outputTokens }

    return TokenUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
      cachedTokens: usage.cacheReadInputTokens,
      reasoningTokens: usage.thinkingTokens,
    )
  }

  func callTool<T: FoundationModels.Tool>(
    _ tool: T,
    with generatedContent: GeneratedContent,
  ) async throws -> T.Output where T.Output: ConvertibleToGeneratedContent {
    let arguments = try T.Arguments(generatedContent)
    return try await tool.call(arguments: arguments)
  }
}
