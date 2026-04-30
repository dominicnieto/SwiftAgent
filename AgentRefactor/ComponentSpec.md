# SwiftAgent Refactor Component Spec

Last verified: 2026-04-29.

## Design Principles

1. `LanguageModel` is the public lowest-level provider/model backend.
2. `LanguageModelSession` is the public stateful low-level inference session.
3. `AgentSession` is the public high-level agent/tool-loop runtime.
4. Providers parse and serialize provider protocols; they do not execute local SwiftAgent tools.
5. Provider-native state is preserved through `providerMetadata`, not a separate `ProviderContinuation`.
6. Streaming and non-streaming share the same neutral model-turn contract.
7. `@SessionSchema` resolves transcript data from either public session type.

## Component 1: LanguageModel

Purpose: one provider turn at a time.

Required shape:

```swift
public protocol LanguageModel: Sendable {
  associatedtype UnavailableReason: Sendable
  associatedtype CustomGenerationOptions: SwiftAgent.CustomGenerationOptions = Never

  var availability: Availability<UnavailableReason> { get }
  var capabilities: LanguageModelCapabilities { get }

  func respond(to request: ModelRequest) async throws -> ModelResponse
  func streamResponse(to request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error>

  func prewarm(for request: ModelPrewarmRequest)
  func logFeedbackAttachment(_ request: FeedbackAttachmentRequest) -> Data
}
```

`ModelRequest` contains messages, instructions, tools, tool choice, structured output request, generation options, and attachments. It does not contain a continuation object.

Provider-specific request reconstruction uses:

- `ModelMessage.providerMetadata`
- `Transcript.*.providerMetadata`
- `ModelAttachment.providerMetadata`
- `ResponseMetadata.providerMetadata`
- provider-specific custom generation options

## Component 2: Model Turn Types

Required public types:

- `ModelRequest`
- `ModelMessage`
- `ModelAttachment`
- `ToolChoice`
- `ToolDefinition`
- `ToolDefinitionKind`
- `StructuredOutputRequest`
- `ResponseFormat`
- `ModelResponse`
- `ModelToolCall`
- `ModelTurnCompletion`
- `ModelStreamEvent`
- `ToolInputStart`
- `ToolCallPartial`
- `ModelSource`
- `ModelFile`

Important constraints:

- `ModelResponse` returns content, transcript entries, tool calls, reasoning, finish reason, usage, metadata, and raw provider output.
- `ModelStreamEvent` exposes typed lifecycle events for text, structured output, reasoning, tool input, completed tool calls, provider tool results, sources/files, usage, metadata, completion, failure, warnings, and raw diagnostics.
- `ModelToolCall.kind` distinguishes `.local` from `.providerDefined`.
- `AgentSession` executes only `.local` tool calls.

## Component 3: ConversationEngine

Purpose: package-internal state machine owned by `LanguageModelSession`.

Responsibilities:

- Store public `Transcript`.
- Build `ModelRequest` from transcript, prompts, tool outputs, tools, active tool filters, structured output requests, images, and generation options.
- Apply `ModelResponse`.
- Reduce `ModelStreamEvent`.
- Accumulate `TokenUsage`.
- Accumulate latest `ResponseMetadata`.
- Produce runtime stream snapshots.
- Preserve prompt groundings for `@SessionSchema`.

It does not own:

- Local tool execution.
- Agent loop stop policy.
- Provider wire formats.
- A separate provider continuation store.

## Component 4: LanguageModelSession

Purpose: public direct model/session API.

Required behavior:

- Own a private `ConversationEngine`.
- Expose transcript, token usage, response metadata, and `isResponding`.
- Provide `respond(...)` and `streamResponse(...)`.
- Provide `respond(with toolOutputs:)` and `streamResponse(with toolOutputs:)`.
- Register tools for model-visible tool schemas without executing them.
- Support structured output, prompt builder, images, groundings, and schema overloads.
- Expose public response snapshots for direct UI use.
- Expose package-only runtime hooks for `AgentSession`.

Must not:

- Execute local tools.
- Loop after tool calls.
- Own retry/approval/missing-tool policy.

## Component 5: AgentSession

Purpose: public high-level runtime for automatic tool execution.

Required behavior:

- Own a `LanguageModelSession`.
- Execute local tool calls.
- Never execute provider-defined/server-side tool calls.
- Enforce max iterations.
- Preserve `ToolRunRejection` recovery.
- Preserve existing tool execution policy behavior.
- Expose typed final output and per-step history.
- Stream model lifecycle, tool lifecycle, partial content, and final events.
- Aggregate token usage and response metadata through its underlying session.

Current implementation deliberately does not add `AgentRuntime` or an agent protocol. Concrete `AgentSession` is enough for phase 8 and for basic future orchestration with multiple sessions.

## Component 6: Provider Requirements

Every provider should:

- Serialize `ModelRequest`.
- Parse `ModelResponse`.
- Parse `ModelStreamEvent`.
- Serialize local tool definitions.
- Serialize provider-defined tool definitions where supported.
- Parse local and provider-defined tool calls distinctly.
- Serialize tool outputs for continuation turns.
- Preserve provider metadata needed by later turns.
- Normalize usage, finish reasons, response metadata, errors, and warnings.

Providers must not:

- Call `Tool.call`.
- Own max-iteration loops.
- Mutate public session transcript directly.
- Depend on `LanguageModelSession`.

## Component 7: Provider Feature Matrices

Provider parity is tracked beside provider implementations:

- `Sources/SwiftAgent/Providers/OpenAI/FEATURE_PARITY.md`
- `Sources/SwiftAgent/Providers/OpenResponses/FEATURE_PARITY.md`
- `Sources/SwiftAgent/Providers/Anthropic/FEATURE_PARITY.md`
- `Sources/SimulatedSession/Simulation/FEATURE_PARITY.md`

These matrices are phase-8/phase-9 inputs. They document provider-doc and AI SDK gaps; they are not all phase-7 completion requirements.

## Explicit Non-Goals Before Phase 8

- Multi-agent orchestration.
- Handoffs.
- Memory/retrieval.
- Approval UI.
- New external providers.
- Full OpenAI/Anthropic hosted-tool parity.
- Full provider-doc parity.
