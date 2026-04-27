# SwiftAgent Refactor Component Spec

## Design Principles

1. The agent loop lives in one runtime, not inside every provider.
2. Providers parse and serialize provider protocols; they do not execute tools.
3. Public transcript and provider-native continuation state are separate.
4. Streaming and non-streaming share the same turn model.
5. `LanguageModelSession` is a stateful conversation API, not an agent.
6. `AgentSession` is the explicit tool/task runtime.
7. Current schema, structured output, prompt builder, transcript, and streaming state features should continue through the public transcript model.

## Component 1: LanguageModel

### Purpose

Raw provider/model adapter. A `LanguageModel` performs one model turn at a time.

### Required API Shape

```swift
public protocol LanguageModel: Sendable {
  associatedtype UnavailableReason: Sendable = Never
  associatedtype CustomGenerationOptions: SwiftAgent.CustomGenerationOptions = Never

  var availability: Availability<UnavailableReason> { get }
  var capabilities: LanguageModelCapabilities { get }

  func respond(to request: ModelRequest) async throws -> ModelResponse

  func streamResponse(
    to request: ModelRequest
  ) -> AsyncThrowingStream<ModelStreamEvent, any Error>

  func prewarm(for request: ModelPrewarmRequest)

  func logFeedbackAttachment(_ request: FeedbackAttachmentRequest) -> Data
}
```

The final names can change, but providers should receive a neutral `ModelRequest`, not a `LanguageModelSession`.

### Required Data Types

```swift
public struct ModelRequest: Sendable {
  public var messages: [ModelMessage]
  public var instructions: Instructions?
  public var tools: [ToolDefinition]
  public var responseFormat: ResponseFormat?
  public var generationOptions: GenerationOptions
  public var continuation: ProviderContinuation?
  public var attachments: [ModelAttachment]
}
```

```swift
public struct ModelResponse: Sendable {
  public var content: GeneratedContent?
  public var transcriptEntries: [Transcript.Entry]
  public var toolCalls: [Transcript.ToolCall]
  public var reasoning: [Transcript.Reasoning]
  public var finishReason: FinishReason
  public var tokenUsage: TokenUsage?
  public var responseMetadata: ResponseMetadata?
  public var continuation: ProviderContinuation?
  public var rawProviderOutput: JSONValue?
}
```

```swift
public enum ModelStreamEvent: Sendable, Equatable {
  case started(ResponseMetadata?)
  case textDelta(id: String, delta: String)
  case structuredDelta(id: String, delta: GeneratedContent)
  case reasoningDelta(id: String, delta: String)
  case reasoningCompleted(Transcript.Reasoning)
  case toolCallPartial(ToolCallPartial)
  case toolCallsCompleted([Transcript.ToolCall], continuation: ProviderContinuation?)
  case usage(TokenUsage)
  case metadata(ResponseMetadata)
  case completed(ModelTurnCompletion)
  case failed(LanguageModelStreamError)
  case raw(JSONValue)
}
```

```swift
public struct ModelTurnCompletion: Sendable, Equatable {
  public var finishReason: FinishReason
  public var continuation: ProviderContinuation?
}
```

### ProviderContinuation

`ProviderContinuation` is the key missing abstraction.

```swift
package struct ProviderContinuation: Sendable, Codable, Equatable {
  package var providerName: String
  package var modelID: String?
  package var turnID: String
  package var payload: JSONValue
}
```

`ProviderContinuation` should stay package/internal because all supported providers live inside SwiftAgent. If it ever becomes public, document it as an advanced provider-authoring type, not an app-facing transcript feature.

The runtime stores it but does not interpret it.

Examples:

- OpenAI Responses stores raw response output items.
- Chat Completions stores assistant tool-call message state.
- Anthropic stores assistant content blocks required for tool result continuation.

### Provider Requirements

Every provider must implement:

- Plain request serialization.
- Tool definition serialization.
- Tool call parsing.
- Tool output continuation serialization.
- Streaming parser into `ModelStreamEvent`.
- Provider continuation creation.
- Provider continuation consumption.
- Usage and response metadata normalization.
- Structured output request support when capability is advertised.

Providers must not:

- Call `Tool.call`.
- Own max iteration loops.
- Mutate a public session transcript directly.
- Reconstruct continuation context from public transcript when provider-native state exists.

## Component 2: ConversationEngine and Shared Components

### Purpose

Internal shared state machine used by `LanguageModelSession` and `AgentSession`.

### Required Responsibilities

- Store public `Transcript`.
- Store provider continuations keyed by turn/tool-call scope.
- Build `ModelRequest`.
- Apply `ModelResponse`.
- Reduce `ModelStreamEvent`.
- Track `TokenUsage`.
- Track latest `ResponseMetadata`.
- Provide typed structured output snapshots.
- Handle prompt entries and image attachments.
- Preserve prompt groundings for `@SessionSchema`.

### API Shape

```swift
package final class ConversationEngine: Sendable {
  package var transcript: Transcript { get }
  package var tokenUsage: TokenUsage? { get }
  package var responseMetadata: ResponseMetadata? { get }

  package init(
    model: any LanguageModel,
    instructions: Instructions?
  )

  package func makeRequest(
    prompt: Prompt?,
    tools: [any Tool],
    responseFormat: ResponseFormat?,
    options: GenerationOptions,
    continuation: ProviderContinuation?
  ) throws -> ModelRequest

  package func apply(_ response: ModelResponse) throws -> ConversationUpdate

  package func reduce(_ event: ModelStreamEvent) throws -> ConversationUpdate

  package func appendToolOutputs(
    _ outputs: [Transcript.ToolOutput],
    after continuation: ProviderContinuation?
  ) throws -> ProviderContinuation?
}
```

### Shared Helper Types

Required helpers:

- `ModelRequestBuilder`
- `ProviderContinuationStore`
- `TranscriptRecorder`
- `ModelEventReducer`
- `StructuredOutputAccumulator`
- `PartialToolCallAccumulator`
- `TokenUsageAccumulator`
- `ResponseMetadataAccumulator`

### Transcript Rules

The transcript stays provider-neutral.

Allowed public transcript entries:

- instructions
- prompt
- reasoning summary
- tool calls
- tool outputs
- response

Provider-native raw state must not be forced into public transcript entries. It belongs in `ProviderContinuationStore`.

## Component 3: LanguageModelSession

### Purpose

Stateful conversation API for direct LLM calls.

### API Shape

```swift
@Observable
public final class LanguageModelSession: @unchecked Sendable {
  public var isResponding: Bool { get }
  public var transcript: Transcript { get }
  public var tokenUsage: TokenUsage? { get }
  public var responseMetadata: ResponseMetadata? { get }

  public init(
    model: any LanguageModel,
    instructions: Instructions? = nil
  )

  public func respond(
    to prompt: Prompt,
    options: GenerationOptions
  ) async throws -> LanguageModelSession.Response<String>

  public func respond<Content: Generable & Sendable>(
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions
  ) async throws -> LanguageModelSession.Response<Content>

  public func streamResponse<Content>(
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions
  ) -> LanguageModelSession.ResponseStream<Content>
    where Content: Generable & Sendable,
          Content.PartiallyGenerated: Sendable
}
```

### Tool Call Policy

`LanguageModelSession` should not automatically execute tools.

Allowed:

- Pass tool definitions for model planning or manual tool-call inspection.
- Return parsed tool calls in `Response`.
- Record model-emitted tool calls in the transcript.

Not allowed:

- Execute tools.
- Continue a tool loop.
- Own max tool rounds.

If an app needs automatic tool execution, use `AgentSession`.

### Existing Feature Continuity

The following README features should continue to work through `LanguageModelSession`:

- Basic text responses.
- Structured responses with `@Generable`.
- Prompt builder.
- Images/attachments where provider supports them.
- Transcript access.
- Token usage.
- Response metadata.
- Reasoning summaries.
- Streaming text.
- Streaming structured output.
- `@SessionSchema` transcript resolution for prompts, groundings, structured outputs, and manually returned tool calls.

Tool execution examples should move from `LanguageModelSession` to `AgentSession`.

## Component 4: AgentSession

### Purpose

Single-agent task runtime with a central tool loop.

### API Shape

```swift
@Observable
public final class AgentSession: @unchecked Sendable {
  public var isRunning: Bool { get }
  public var transcript: Transcript { get }
  public var tokenUsage: TokenUsage? { get }
  public var responseMetadata: ResponseMetadata? { get }

  public init(
    model: any LanguageModel,
    tools: [any Tool] = [],
    instructions: Instructions? = nil,
    configuration: AgentConfiguration = .default
  )

  public func run(
    _ input: String,
    options: GenerationOptions
  ) async throws -> AgentResult<String>

  public func run<Content: Generable & Sendable>(
    _ input: String,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions
  ) async throws -> AgentResult<Content>

  public func stream<Content>(
    _ input: String,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions
  ) -> AsyncThrowingStream<AgentEvent<Content>, any Error>
    where Content: Generable & Sendable,
          Content.PartiallyGenerated: Sendable
}
```

### AgentConfiguration

```swift
public struct AgentConfiguration: Sendable, Equatable {
  public var maxIterations: Int
  public var toolExecutionPolicy: ToolExecutionPolicy
  public var stopOnToolError: Bool
}
```

Initial scope should include only:

- `maxIterations`: prevents runaway model/tool loops.
- `toolExecutionPolicy`: reuses the existing automatic/delegate/stop behavior.
- `stopOnToolError`: controls whether failed tools abort the run or are returned to the model as recoverable output.

Streaming throttling such as `minimumStreamingSnapshotInterval` should remain in `GenerationOptions` unless agent streaming later needs a separate event-throttling policy.

Initial scope should not include memory, handoffs, approvals, retries, or guardrails, but the config should leave room for them.

### Sendability and State Isolation

`AgentSession` should use the same concurrency pattern as `LanguageModelSession`: `@unchecked Sendable` plus locked mutable state.

Rules:

- Store mutable observable state inside a locked state container.
- Do not hold locks across `await`.
- Snapshot state before async model/tool work.
- Re-enter the lock only to publish durable state changes.
- Keep high-frequency stream events out of locked observable state unless they are also durable session state.

### Observation Model

`AgentSession` should be `@Observable`, but observable state should stay durable and low-frequency. High-frequency chat activity should be delivered through `stream(...)`.

Observable properties:

```swift
public var isRunning: Bool { get }
public var transcript: Transcript { get }
public var tokenUsage: TokenUsage? { get }
public var responseMetadata: ResponseMetadata? { get }
public var currentIteration: Int { get }
public var currentToolCalls: [Transcript.ToolCall] { get }
public var currentToolOutputs: [Transcript.ToolOutput] { get }
public var latestError: Error? { get }
```

Optional/debug-only:

```swift
public var latestEvent: AgentEventSummary? { get }
```

`latestEvent` should not be the primary chat UI delivery mechanism because agent events are transient and can be emitted faster than observation-driven UI state should model. Chat UI should consume `AgentSession.stream(...)` and append/render events explicitly.

If added, `latestEvent` should be documented as a debugging and diagnostics aid, not as the main event stream. Practical uses:

- A debug inspector showing the last agent event.
- Logging or breakpoint-oriented diagnostics while developing providers/tools.
- A lightweight status label such as "Calling weather tool..." when the exact full event history does not matter.

### AgentResult

```swift
public struct AgentResult<Content: Sendable>: Sendable {
  public var content: Content
  public var rawContent: GeneratedContent
  public var transcript: Transcript
  public var toolCalls: [Transcript.ToolCall]
  public var toolOutputs: [Transcript.ToolOutput]
  public var tokenUsage: TokenUsage?
  public var responseMetadata: ResponseMetadata?
  public var iterationCount: Int
}
```

### AgentEvent

```swift
public enum AgentEvent<Content>: Sendable
where Content: Generable & Sendable,
      Content.PartiallyGenerated: Sendable {
  case started
  case iterationStarted(Int)
  case modelEvent(ModelStreamEvent)
  case partialContent(Content.PartiallyGenerated)
  case toolCallStarted(Transcript.ToolCall)
  case toolCallCompleted(Transcript.ToolCall)
  case toolOutput(Transcript.ToolOutput)
  case iterationCompleted(Int)
  case completed(AgentResult<Content>)
  case failed(Error)
}
```

`AgentEvent` should mirror `LanguageModelSession.ResponseStream`: streamed content must be `Generable`, and its partial representation must be `Sendable`.

This covers both normal text and structured output:

- `String` conforms to `Generable`, and its partial representation is another `String`.
- A macro-generated structured type conforms to `Generable`, and its partial representation is the macro-generated draft type.

### Loop Contract

Agent loop:

```text
1. Build initial prompt.
2. Request model turn with tools.
3. Apply streamed or complete model response.
4. If no tool calls, finish.
5. Execute tool calls.
6. Append tool outputs.
7. Continue model turn with provider continuation state.
8. Repeat until final response or max iterations.
```

### Existing Feature Continuity

The following current README features should move to or also work with `AgentSession`:

- Tool execution.
- Tool run rejection and recoverable tool errors.
- Streaming while the agent thinks, calls tools, and produces final output.
- Typed tool run resolution via `@SessionSchema`.
- Structured final output.
- Transcript access.
- Token usage aggregation across iterations.
- Provider metadata for latest turn and possibly per-turn metadata later.

`@SessionSchema` should continue to resolve `AgentSession.transcript` because the transcript shape remains shared.

## Resolved Decisions

1. `LanguageModelSession` may accept tool schemas for manual tool-call inspection, but it must not execute tools automatically.
2. `ProviderContinuation` should be package/internal while all providers live in SwiftAgent.
3. Rename the schema protocol to a runtime-neutral name. Current preference: `TranscriptSchema`.
4. `AgentSession` should use `run` and `stream`, not `respond` and `streamResponse`, because it may perform multiple model/tool iterations before producing a final result.
