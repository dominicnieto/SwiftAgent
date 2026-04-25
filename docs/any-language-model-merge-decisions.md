# AnyLanguageModel Merge Decisions

This file tracks architectural decisions and open questions for the merge.

## Accepted Direction

### No Bridge Architecture

Decision: The final architecture should not contain a bridge between SwiftAgent's current adapters and AnyLanguageModel's sessions.

Rationale: The goal is one coherent model stack. A bridge preserves duplicate abstractions, makes transcript fidelity harder to reason about, and keeps the old adapter boundary alive longer than necessary.

### Transcript Must Be Agent-Grade

Decision: The merged transcript must be a superset of SwiftAgent's current agent transcript and AnyLanguageModel's FoundationModels-compatible transcript.

Rationale: AnyLanguageModel's current transcript is useful for drop-in FoundationModels compatibility, but it does not provide enough visibility for agent UIs, tool execution, reasoning, token usage, and transcript resolution.

### Streaming Is Transcript-First

Decision: Providers should emit updates that mutate transcript/token state, and public snapshots should be derived from that state.

Rationale: Content-only snapshots are too limiting for agents. Tool calls, tool outputs, reasoning, and usage need to be visible during generation.

### GenerationOptions Should Be Unified

Decision: Use one `GenerationOptions` type with common options and model-specific custom options.

Rationale: Separate provider option types force session/provider specialization into user code. Custom options preserve provider power without duplicating the session API.

## Open Questions

### Module Naming

Decision: Fold the moved AnyLanguageModel core into SwiftAgent's public API instead of keeping `AnyLanguageModel` as a visible long-term module.

Rationale: This is a private repo with no existing app consumers, so the cleanest end state is more valuable than compatibility staging. A temporary SwiftPM target can still be used during migration if it makes source movement easier to review, but the final user-facing API should feel like one SwiftAgent model stack.

Implication: Docs and examples should eventually import SwiftAgent only, unless optional provider products require a provider-specific import.

### Public Session Names

Decision: Design around the clean canonical API, not compatibility session names.

Preferred shape:

```swift
let session = LanguageModelSession(
  model: OpenAILanguageModel(apiKey: key, model: "gpt-5.2"),
  tools: [weatherTool],
  instructions: "You are helpful."
)
```

Rationale: There are no existing users to migrate. `OpenAISession` and `AnthropicSession` should not be preserved unless they remain useful as thin convenience APIs.

### Transcript Token Usage Placement

Decision: Keep token usage on session, response, and streaming snapshot state, not as transcript entries.

Rationale: Token usage is metadata about provider execution, not conversational content. It should stream alongside transcript updates without becoming part of the model-visible transcript.

Current SwiftAgent behavior: `AdapterUpdate.tokenUsage(TokenUsage)` is separate from `AdapterUpdate.transcript(...)`; sessions merge usage into `tokenUsage`; `AgentResponse` and `AgentSnapshot` expose usage; `Transcript.Entry` has no usage case.

### Reasoning Representation

Decision: Keep reasoning as its own transcript entry.

Rationale: Reasoning is not normal assistant output and may have different visibility, persistence, and provider semantics.

Current SwiftAgent behavior: `Transcript.Entry.reasoning(Reasoning)` stores `id`, `summary`, `encryptedReasoning`, and `status`. OpenAI adapters already emit reasoning entries for streaming and non-streaming paths.

### Provider Capabilities

Decision: Use a hybrid provider capability model.

SwiftAgent should take these patterns from the inspected SDKs:

- Conduit-style separation between model, provider, and runtime capabilities.
- Swarm-style `OptionSet` flags for simple checks and protocol inference.
- Swift AI SDK-style rich streaming event enum for provider-to-session streaming.

Rationale: Model, provider, and runtime capabilities answer different questions. `OptionSet` flags keep common checks ergonomic. Protocol inference avoids boilerplate for capabilities implied by provider conformance. Rich stream events preserve actual run behavior and should not be replaced by static capability flags.

Capability examples:

- supports tool call streaming
- supports structured output natively
- supports image input
- supports reasoning summaries
- supports token usage during streaming
- supports parallel tool calls

Capabilities should guide validation, fallback behavior, UI affordances, and tests. They should not excuse missing agent-grade streaming work for providers that can support it.

### Compatibility With Apple FoundationModels

Decision: Agent capability overrides exact Apple FoundationModels compatibility when they conflict.

Rationale: The merged core can keep useful FoundationModels concepts, but it should not contort the agent architecture to match Apple's API exactly. Names like `Generable`, `GeneratedContent`, `Tool`, and `LanguageModelSession` are useful; agent-grade transcript and streaming behavior are more important than drop-in source compatibility.

Clarification: Compatibility means API shape and conceptual familiarity, not importing Apple's `FoundationModels` module.

### Optional Provider Dependencies

Decision: Keep heavy or platform-specific providers optional.

Rationale: MLX, CoreML, Llama, and similar local providers have platform, binary, model-loading, or dependency costs that should not burden the base package.

Chosen strategy: Use a folded core API in `SwiftAgent`, separate optional provider targets/products for heavy local providers, and SwiftPM traits only where they genuinely simplify conditional dependencies.

### Tool Execution Policy

Decision: Tool execution policy belongs at the session layer.

Rationale: Providers should emit tool calls and consume tool outputs. The session engine should decide whether tools execute in parallel, whether failures retry, how missing tools are represented, and whether approval is required.

### Provider Metadata and Rate Limits

Decision: Normalize provider response metadata outside the transcript.

Rationale: Request IDs, provider request IDs, rate-limit state, retry-after hints, model IDs, and warnings are execution metadata. They are useful in responses, snapshots, logs, and replay fixtures, but should not become model-visible transcript content.

### Logging

Decision: Preserve SwiftAgent's logging direction and fold provider logging into it.

Rationale: SwiftAgent already has useful run lifecycle logging, token usage logging, network logging, and replay recording. The merged package should extend that model for normalized stream events, warnings, and metadata rather than adopting separate provider-local logging systems.

### Transcript Replay and Diff

Decision: Add transcript schema versioning and focused diff helpers.

Rationale: This helps review provider fixture changes, verify streaming transcript assembly, and make the SwiftAgent/AnyLanguageModel transcript merge safer.

### Structured Output Source

Decision: Track how structured output was produced.

Rationale: Provider-native structured output, prompt fallback parsing, and constrained decoding have different reliability and failure modes. Tests and debugging should be able to distinguish them.

## Risks

### Streaming Provider Gaps

Decision: Streaming provider gaps are priority implementation work, not optional polish.

Some AnyLanguageModel providers currently stream content snapshots and ignore or minimize tool event handling. These implementations must be upgraded before they can replace SwiftAgent's agent-grade streaming behavior.

### Duplicate Type Removal

Removing duplicate `Transcript`, `LanguageModelSession`, and `GenerationOptions` types will touch many files and macros. This should be done in vertical slices with tests.

### Test Fixture Drift

Provider request/response formats will change when SDKs are removed. Replay fixtures should be updated intentionally and reviewed as API behavior, not incidental churn.
