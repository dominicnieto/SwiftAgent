# AnyLanguageModel Merge Spec

## Purpose

Merge AnyLanguageModel into SwiftAgent as the canonical model foundation and provider implementation layer. The target is one coherent SwiftAgent model stack, not two packages connected by adapter bridges.

SwiftAgent should keep its agent-focused ergonomics, schema macros, transcript resolution, grounding, token accounting, and UI streaming behavior. AnyLanguageModel should contribute the FoundationModels-compatible core primitives and direct provider implementations that remove the need for Apple's FoundationModels module and provider SDK dependencies.

## Non-Goals

- Do not add AnyLanguageModel as a permanent external package dependency.
- Do not keep a long-term bridge where SwiftAgent adapters translate into AnyLanguageModel sessions.
- Do not preserve duplicate canonical definitions for `Transcript`, `LanguageModelSession`, `GenerationOptions`, `Tool`, `GeneratedContent`, or `GenerationSchema`.
- Do not regress SwiftAgent's agent transcript fidelity to content-only streaming snapshots.
- Do not optimize for exact Apple FoundationModels source compatibility when it conflicts with agent capability.

## Target Architecture

The merged package should expose one model stack:

```text
SwiftAgent package
  Core model primitives
    Generable
    GeneratedContent
    GenerationSchema
    Prompt
    Instructions
    Tool
    Transcript
    GenerationOptions
    LanguageModel
    LanguageModelSession

  Direct providers
    OpenAILanguageModel
    OpenResponsesLanguageModel
    AnthropicLanguageModel
    GeminiLanguageModel
    OllamaLanguageModel
    MLXLanguageModel
    CoreMLLanguageModel
    LlamaLanguageModel

  Agent layer
    @SessionSchema
    grounding
    resolved transcript types
    agent responses and snapshots
    token usage
    logging
    replay recording fixtures
```

`LanguageModel` providers become the provider boundary. SwiftAgent's current `Adapter` layer should be removed or reduced to temporary implementation scaffolding during migration only.

The final public API should be folded into SwiftAgent rather than exposing AnyLanguageModel as a long-term separate module. Temporary target boundaries are allowed only to keep migration steps reviewable.

## Canonical Type Ownership

### Model Primitives

AnyLanguageModel's replacements for FoundationModels primitives should become the canonical local definitions:

- `Generable`
- `GeneratedContent`
- `GenerationSchema`
- `DynamicGenerationSchema`
- `GenerationGuide`
- `Prompt`
- `Instructions`
- `Tool`
- `LanguageModel`
- `Availability`

SwiftAgent code and macros should emit and consume these local definitions directly.

### LanguageModelSession

The merged `LanguageModelSession` should be the primary session engine for all providers.

It should own:

- selected `LanguageModel`
- tools
- instructions
- rich transcript
- cumulative token usage
- `isResponding`
- respond and stream APIs
- tool execution policy/delegate hooks
- schema/grounding integration hooks needed by SwiftAgent

Provider-specific session types like `OpenAISession` and `AnthropicSession` are not required for compatibility because there are no existing app consumers. If they remain, they should be thin convenience APIs over the canonical session rather than parallel session architectures.

### GenerationOptions

Use one `GenerationOptions` type with shared fields and provider-specific custom options.

Shared fields should include:

- sampling mode
- temperature
- maximum response tokens
- minimum streaming snapshot interval

Provider-specific options should attach by model type, for example:

```swift
var options = GenerationOptions(
  temperature: 0.7,
  maximumResponseTokens: 1024
)

options[custom: OpenAILanguageModel.self] = .init(
  reasoningEffort: .medium,
  store: false
)
```

SwiftAgent's current `OpenAIGenerationOptions` and `AnthropicGenerationOptions` should be folded into this model, preserving source-compatible convenience initializers only if useful.

## Transcript Model

AnyLanguageModel's current transcript is too limited for agent UX. The merged transcript should be a superset, biased toward SwiftAgent's agent-grade transcript semantics while adding AnyLanguageModel's FoundationModels-compatible concepts.

Canonical entries:

```swift
public enum Transcript.Entry {
  case instructions(Instructions)
  case prompt(Prompt)
  case reasoning(Reasoning)
  case toolCalls(ToolCalls)
  case toolOutput(ToolOutput)
  case response(Response)
}
```

Canonical segments:

```swift
public enum Transcript.Segment {
  case text(TextSegment)
  case structure(StructuredSegment)
  case image(ImageSegment)
}
```

Required transcript capabilities:

- instruction entries with tool definitions
- prompts with original input, grounding/source metadata, response format, options, and multimodal segments
- reasoning entries with summary, encrypted reasoning payload, and status
- tool calls with provider correlation IDs and status
- tool outputs with provider correlation IDs and status
- responses with text or structured segments and status
- structured segments that can identify their output type/source
- codable, sendable, equatable transcript storage
- stable IDs for upsert-style streaming updates
- resolved transcript APIs for `@SessionSchema`
- schema versioning and focused diff helpers for replay fixture review
- structured output source tracking for provider-native, prompt-fallback, and constrained-decoder outputs

Token usage should remain a session/update concern rather than being embedded directly into every transcript entry.

## Streaming Model

The merged streaming model should preserve SwiftAgent's transcript fidelity. Content snapshots alone are insufficient for agents.

Providers should emit a stream of model updates. The session engine should mutate transcript/token state from those updates and derive public snapshots from the current state.

Internal update shape:

```swift
public enum LanguageModelUpdate {
  case transcript(Transcript.Entry)
  case tokenUsage(TokenUsage)
}
```

Public snapshot shape:

```swift
public struct ResponseStream<Content> {
  public struct Snapshot {
    public var content: Content.PartiallyGenerated?
    public var rawContent: GeneratedContent?
    public var transcript: Transcript
    public var tokenUsage: TokenUsage
  }
}
```

Streaming requirements:

- emit prompt entries at the start of a turn
- emit response text deltas as upserted response entries
- emit partial structured content when valid partial content can be decoded
- emit tool calls while streaming, including argument deltas when the provider supports them
- emit tool outputs when tools complete
- emit reasoning summaries and encrypted reasoning payloads when providers expose them
- emit token usage as soon as providers report it
- support throttled snapshots for UI use
- always emit a final snapshot representing the completed transcript state
- emit provider warnings and response metadata when available

Agent-grade streaming parity is required for provider replacement. Providers that currently emit only content snapshots must be upgraded before they are considered migrated.

## Tool Execution

Tool execution should be configured at the session layer rather than hidden inside provider implementations.

Required policy controls:

- parallel tool execution on/off
- retry policy for retryable tool failures
- missing-tool behavior
- tool failure behavior
- optional approval hook before execution

Provider implementations should emit tool calls and receive tool outputs; the session engine should own execution policy.

## Provider Layer

Direct providers from AnyLanguageModel should replace SDK-based SwiftAgent adapters:

- `OpenAILanguageModel` and/or `OpenResponsesLanguageModel` replace `OpenAIAdapter`
- `AnthropicLanguageModel` replaces `AnthropicAdapter`
- additional providers become available through the same `LanguageModel` boundary

Provider implementations must be upgraded where needed to emit agent-grade streaming updates rather than only content snapshots.

Provider implementations should not depend on MacPaw/OpenAI or SwiftAnthropic.

Provider responses should expose normalized metadata where available:

- SwiftAgent request ID
- provider request ID
- provider model ID
- rate-limit state
- retry-after hints
- provider warnings

Provider differences should be represented explicitly when they affect behavior. Use a hybrid capability and streaming design:

- Conduit-style separation between model, provider, and runtime capabilities.
- Swarm-style `OptionSet` flags for simple checks and protocol inference.
- Swift AI SDK-style rich streaming event enum for provider-to-session streaming.

Capabilities should describe support for streaming tool calls, native structured output, image input, reasoning summaries, token usage during streaming, parallel tool calls, and similar feature branches. Static capabilities should guide validation, fallback behavior, UI affordances, and test expectations; rich streaming events should still describe what is happening in a specific run.

Heavy or platform-specific providers should remain optional. For this repo, prefer a folded core API in `SwiftAgent`, separate optional provider targets/products for heavy local providers, and SwiftPM traits only where they genuinely simplify conditional dependencies.

Example package shape:

```swift
.library(name: "SwiftAgent", targets: ["SwiftAgent"]),
.library(name: "SwiftAgentMLX", targets: ["SwiftAgentMLX"]),
.library(name: "SwiftAgentLlama", targets: ["SwiftAgentLlama"]),
```

The base SwiftAgent build should not require MLX, CoreML, Llama, or similar local-provider dependencies unless the user opts into them.

## Macro Impact

SwiftAgent macros should generate code against the merged local primitives.

Expected updates:

- `@SessionSchema` tool storage should use the canonical `Tool`
- structured output declarations should use the canonical `Generable` and `GeneratedContent`
- generated transcript resolver code should target the merged transcript
- documentation examples should import the canonical SwiftAgent module(s), not Apple FoundationModels

## Logging

SwiftAgent's existing logging approach should be preserved and expanded:

- keep `AgentLog`-style lifecycle logging for runs, steps, tool calls, reasoning, structured output, and token usage
- keep opt-in `NetworkLog`-style raw HTTP logging
- keep replay-recorder-friendly request/response capture
- add provider warning and normalized stream-event logging where useful
- add redaction hooks for credentials and sensitive tool outputs

AnyLanguageModel provider-local logging should be folded into this logging story rather than becoming a separate logging layer.

## Compatibility Strategy

Compatibility should be preserved where it does not force duplicate architecture.

Acceptable compatibility:

- convenience `OpenAISession` and `AnthropicSession` constructors over `LanguageModelSession`
- typealiases or deprecated wrappers during migration
- option conversion helpers while tests move over

Not acceptable as final architecture:

- provider SDK adapters as the real implementation path
- parallel transcript models
- permanent SwiftAgent-to-AnyLanguageModel bridge sessions

## Success Criteria

- SwiftAgent builds without importing Apple `FoundationModels` in core agent code.
- SwiftAgent builds without MacPaw/OpenAI and SwiftAnthropic provider SDK dependencies.
- Existing SwiftAgent OpenAI and Anthropic behavior is covered by tests or intentionally replaced.
- Streaming tests verify transcript updates for text, structured output, tool calls, tool output, reasoning where available, and token usage.
- AnyLanguageModel provider tests are brought into the repo and adapted to the merged APIs.
- README examples use the merged model/session API.
