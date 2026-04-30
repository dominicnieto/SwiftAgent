// By Dennis Müller

import Foundation
import OSLog
import SwiftAgent

/// A deterministic language model for tests, previews, and examples.
public actor SimulationLanguageModel: LanguageModel {
  public typealias UnavailableReason = Never
  public typealias CustomGenerationOptions = SimulationGenerationOptions

  private let configuration: SimulationConfiguration
  private let configuredDefaultGenerations: [SimulatedGeneration]
  private var nextDefaultGenerationIndex: Int

  /// Creates a simulation model from a fixed generation configuration.
  public init(configuration: SimulationConfiguration) {
    self.configuration = configuration
    configuredDefaultGenerations = configuration.defaultGenerations
    nextDefaultGenerationIndex = 0
  }

  public nonisolated var capabilities: LanguageModelCapabilities {
    LanguageModelCapabilities(
      model: ModelCapabilities(supportsTextGeneration: true),
      provider: [.textStreaming, .structuredOutputs, .toolCalling, .tokenUsage],
    )
  }

  public func respond(to request: ModelRequest) async throws -> ModelResponse {
    let resolvedOptions = try resolveOptions(from: request.generationOptions)
    let promptPreview = request.messages.last?.segments.description ?? ""
    let result = try await runGenerations(
      resolvedOptions.simulatedGenerations,
      tokenUsage: resolvedOptions.tokenUsageOverride ?? configuration.tokenUsage,
      generationDelay: configuration.generationDelay,
      promptPreview: promptPreview,
    )

    return ModelResponse(
      content: result.rawContent,
      transcriptEntries: result.transcriptEntries,
      finishReason: .completed,
      tokenUsage: result.tokenUsage,
      responseMetadata: ResponseMetadata(providerName: "Simulation", modelID: "simulated"),
    )
  }

  public nonisolated func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let resolvedOptions = try await resolveOptions(from: request.generationOptions)
          let tokenUsage = resolvedOptions.tokenUsageOverride ?? configuration.tokenUsage
          let promptPreview = request.messages.last?.segments.description ?? ""

          for generation in resolvedOptions.simulatedGenerations {
            try await Task.sleep(for: configuration.generationDelay)
            let update = try await update(for: generation)
            for entry in update.transcriptEntries {
              switch entry {
              case let .reasoning(reasoning):
                continuation.yield(.reasoningCompleted(reasoning))
              case let .toolCalls(toolCalls):
                continuation.yield(.toolCallsCompleted(toolCalls.calls.map { ModelToolCall(call: $0, kind: .local) }))
              case let .toolOutput(output):
                continuation.yield(.providerToolResult(output))
              default:
                continuation.yield(.raw(try JSONValue(entry)))
              }
            }
            if let rawContent = update.rawContent {
              if case let .string(text) = rawContent.kind {
                continuation.yield(.textStarted(id: "simulation-text", metadata: nil))
                continuation.yield(.textDelta(id: "simulation-text", delta: text))
                continuation.yield(.textCompleted(id: "simulation-text", metadata: nil))
              } else {
                continuation.yield(.structuredDelta(id: "simulation-structured", delta: rawContent))
              }
            }
          }

          if let tokenUsage {
            continuation.yield(.usage(tokenUsage))
          }
          continuation.yield(.metadata(ResponseMetadata(providerName: "Simulation", modelID: "simulated")))
          continuation.yield(.completed(.init(finishReason: .completed)))
          continuation.finish()
          _ = promptPreview
        } catch {
          AgentLog.error(error, context: "simulation_language_model")
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

private extension SimulationLanguageModel {
  struct SimulationResult: Sendable {
    var transcriptEntries: [Transcript.Entry]
    var rawContent: GeneratedContent
    var tokenUsage: TokenUsage?
  }

  func resolveOptions(from options: GenerationOptions) throws -> SimulationGenerationOptions {
    if let customOptions = options[custom: SimulationLanguageModel.self],
       customOptions.simulatedGenerations.isEmpty == false {
      return customOptions
    }

    if nextDefaultGenerationIndex < configuredDefaultGenerations.count {
      return SimulationGenerationOptions(
        simulatedGenerations: dequeueConfiguredDefaultGenerationsForNextTurn(),
        tokenUsageOverride: configuration.tokenUsage,
      )
    }

    throw SimulationConfigurationError.missingGenerations
  }

  /// Consumes all generations up to and including the next final response.
  func dequeueConfiguredDefaultGenerationsForNextTurn() -> [SimulatedGeneration] {
    var turnGenerations: [SimulatedGeneration] = []

    while nextDefaultGenerationIndex < configuredDefaultGenerations.count {
      let generation = configuredDefaultGenerations[nextDefaultGenerationIndex]
      nextDefaultGenerationIndex += 1
      turnGenerations.append(generation)

      switch generation {
      case .textResponse, .structuredResponse:
        return turnGenerations
      case .reasoning, .toolRun:
        continue
      }
    }

    return turnGenerations
  }

  func runGenerations(
    _ generations: [SimulatedGeneration],
    tokenUsage: TokenUsage?,
    generationDelay: Duration,
    promptPreview: String,
  ) async throws -> SimulationResult {
    AgentLog.start(
      model: "simulated",
      toolNames: generations.compactMap(\.toolName),
      promptPreview: promptPreview,
    )
    defer { AgentLog.finish() }

    var entries: [Transcript.Entry] = []
    var rawContent: GeneratedContent?

    for (index, generation) in generations.enumerated() {
      try await Task.sleep(for: generationDelay)
      AgentLog.stepRequest(step: index + 1)
      let update = try await update(for: generation)
      entries.append(contentsOf: update.transcriptEntries)
      rawContent = update.rawContent ?? rawContent
    }

    if let usage = tokenUsage {
      logTokenUsage(usage)
    }

    guard let rawContent else {
      throw SimulationConfigurationError.missingGenerations
    }

    return SimulationResult(transcriptEntries: entries, rawContent: rawContent, tokenUsage: tokenUsage)
  }

  func update(for generation: SimulatedGeneration) async throws -> (transcriptEntries: [Transcript.Entry], rawContent: GeneratedContent?) {
    switch generation {
    case let .reasoning(summary):
      return ([reasoningEntry(summary: summary)], nil)

    case let .toolRun(toolMock):
      return try await toolEntries(for: toolMock)

    case let .textResponse(text):
      AgentLog.outputMessage(text: text, status: "completed")
      return ([], GeneratedContent(text))

    case let .structuredResponse(content):
      AgentLog.outputStructured(json: content.stableJsonString, status: "completed")
      return ([], content)
    }
  }

  func reasoningEntry(summary: String) -> Transcript.Entry {
    AgentLog.reasoning(summary: [summary])
    return .reasoning(
      Transcript.Reasoning(
        id: UUID().uuidString,
        summary: [summary],
        encryptedReasoning: "",
        status: .completed,
      ),
    )
  }

  func toolEntries(for toolMock: some MockableTool) async throws -> (transcriptEntries: [Transcript.Entry], rawContent: GeneratedContent?) {
    let sendableTool = UnsafelySendableMockTool(mock: toolMock)
    let toolName = sendableTool.toolName
    let callId = UUID().uuidString
    let arguments = sendableTool.arguments

    let toolCall = Transcript.ToolCall(
      id: UUID().uuidString,
      callId: callId,
      toolName: toolName,
      arguments: arguments,
      status: .completed,
    )

    AgentLog.toolCall(name: toolName, callId: callId, argumentsJSON: arguments.stableJsonString)

    do {
      let output = try await sendableTool.mockOutput().generatedContent
      return ([.toolCalls(Transcript.ToolCalls(calls: [toolCall])), toolOutput(
        callId: callId,
        toolName: toolName,
        output: output,
      )], nil)
    } catch let rejection as ToolRunRejection {
      return ([.toolCalls(Transcript.ToolCalls(calls: [toolCall])), toolOutput(
        callId: callId,
        toolName: toolName,
        output: rejection.generatedContent,
      )], nil)
    } catch {
      AgentLog.error(error, context: "tool_call_failed_\(toolName)")
      throw GenerationError.toolExecutionFailed(toolName: toolName, underlyingError: error)
    }
  }

  func toolOutput(callId: String, toolName: String, output: GeneratedContent) -> Transcript.Entry {
    AgentLog.toolOutput(name: toolName, callId: callId, outputJSONOrText: output.stableJsonString)
    return .toolOutput(Transcript.ToolOutput(
      id: UUID().uuidString,
      callId: callId,
      toolName: toolName,
      segment: .structure(Transcript.StructuredSegment(content: output)),
      status: .completed,
    ))
  }

  func decode<Content>(_ rawContent: GeneratedContent, as type: Content.Type) throws -> Content where Content: Generable {
    if type == String.self {
      guard case let .string(text) = rawContent.kind else {
        return rawContent.jsonString as! Content
      }
      return text as! Content
    }
    return try type.init(rawContent)
  }

  func logTokenUsage(_ usage: TokenUsage) {
    AgentLog.tokenUsage(
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      totalTokens: usage.totalTokens,
      cachedTokens: usage.cachedTokens,
      reasoningTokens: usage.reasoningTokens,
    )
  }
}

/// Wraps a mockable tool so it can cross `await` boundaries inside the simulation model.
private struct UnsafelySendableMockTool<Mock>: @unchecked Sendable where Mock: MockableTool {
  let mock: Mock

  init(mock: Mock) {
    self.mock = mock
  }

  var arguments: GeneratedContent {
    mock.mockArguments().generatedContent
  }

  var toolName: String {
    mock.tool.name
  }

  func mockOutput() async throws -> Mock.Tool.Output {
    try await mock.mockOutput()
  }
}
