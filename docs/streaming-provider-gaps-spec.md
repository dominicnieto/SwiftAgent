# Streaming Provider Gaps Spec

## Purpose

Define the streaming parity work required before AnyLanguageModel providers can replace SwiftAgent's current agent-capable provider paths.

Content-only streaming is not sufficient. The merged SwiftAgent stack needs transcript-first streaming so agent UIs, logs, replay fixtures, and debugging tools can observe the full run while it is happening.

## Required Streaming Contract

Each provider should emit normalized updates into the main session engine:

```swift
public enum LanguageModelUpdate {
  case transcript(Transcript.Entry)
  case tokenUsage(TokenUsage)
}
```

The session engine owns transcript mutation, status transitions, token usage accumulation, throttling, and public snapshot derivation.

Public snapshots should include:

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

## Normalized Streaming Events

Providers should map native stream events into these transcript/update categories where supported:

- prompt started
- response item created
- response text delta
- response text completed
- structured output delta
- structured output completed
- tool call created
- tool call argument delta
- tool call completed
- tool output started
- tool output completed
- reasoning started
- reasoning summary delta
- reasoning completed
- encrypted reasoning/signature received
- token usage received
- response completed
- response incomplete/failed/cancelled

If a provider cannot support a category, that limitation should be explicit through provider capabilities and covered by tests.

## Provider Matrix

### OpenAI Responses

Primary docs:

- https://platform.openai.com/docs/api-reference/responses-streaming
- https://platform.openai.com/docs/api-reference/responses

Observed capability from docs:

- SSE event model for Responses streaming.
- Text deltas via response output text events.
- Function/tool argument deltas via response function call argument events.
- Reasoning and reasoning summary events for reasoning-capable models.
- Usage is available on response objects and should be emitted when present.

Required work:

- Preserve or port SwiftAgent's existing OpenAI event decoder behavior.
- Normalize output item creation, text deltas, function call argument deltas, reasoning events, completion status, and token usage.
- Preserve encrypted reasoning handling for models that require reasoning continuity across turns.
- Add replay tests for streamed text, streamed tool calls, streamed reasoning, and final token usage.

### Open Responses-Compatible Providers

Primary docs:

- https://www.openresponses.org/

Observed capability from docs:

- The spec is designed around messages, tool calls, streaming, and multimodal inputs.
- It aims to provide consistent streaming events and tool invocation patterns across providers.

Required work:

- Treat Open Responses as a normalized provider input, not as a substitute for SwiftAgent's internal transcript model.
- Map item-based output, tool invocation, and stream events into the main transcript/update contract.
- Add conformance tests against Open Responses acceptance behavior where practical.

### Anthropic Messages

Primary docs:

- https://platform.claude.com/docs/en/build-with-claude/streaming
- https://docs.anthropic.com/en/release-notes/api

Observed capability from docs:

- Streaming uses message and content block events.
- Tool use arguments stream as `input_json_delta` partial JSON.
- Extended thinking streams `thinking_delta` events.
- A signature delta is sent before the thinking content block stops.
- Fine-grained tool streaming is gated by a beta header.

Required work:

- Normalize `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, message deltas, and message stop.
- Accumulate tool input JSON deltas into `Transcript.ToolCall.arguments`.
- Emit reasoning entries for thinking deltas and store the signature/encrypted payload.
- Emit token usage when Anthropic sends usage metadata.
- Add tests for normal text streaming, tool-use JSON deltas, thinking deltas, signature deltas, and beta fine-grained tool streaming.

### Gemini

Primary docs:

- https://ai.google.dev/gemini-api/docs/text-generation
- https://ai.google.dev/gemini-api/docs/function-calling

Observed capability from docs:

- `generateContentStream` returns incremental `GenerateContentResponse` chunks.
- Function calling returns `functionCall` objects with IDs, names, and arguments.
- Function calling modes include `AUTO`, `ANY`, and `NONE`.
- Gemini supports multimodal inputs.
- Gemini exposes thinking configuration for supported models.

Required work:

- Verify whether function call parts appear incrementally in streaming responses or only in completed candidates for the model/API versions SwiftAgent targets.
- Normalize streamed text chunks into response entries.
- Normalize function call parts into tool call transcript entries with stable IDs.
- Normalize function responses in follow-up turns.
- Capture finish reasons and safety/block states as response status or provider errors.
- Add tests for streaming text, function calling, multimodal prompt preservation, and finish reason handling.

### Ollama

Primary docs:

- https://docs.ollama.com/
- https://ollama.com/blog/streaming-tool

Observed capability from docs:

- Ollama supports API streaming.
- Ollama announced streaming responses with tool calling in May 2025.
- Streaming tool support depends on model support.

Required work:

- Use the chat API with `stream: true` and tools.
- Normalize streamed content chunks into response entries.
- Normalize tool calls into transcript tool call entries.
- Determine whether Ollama provides stable tool call IDs; synthesize stable IDs when it does not.
- Add model capability checks or documented warnings for models that do not support tool calling.
- Add tests using local/replayable Ollama responses for streaming text and streaming tool calls.

### MLX Swift LM

Primary docs:

- https://github.com/ml-explore/mlx-swift-lm
- https://github.com/ml-explore/mlx-swift-lm/releases

Observed capability from docs:

- MLX Swift LM is a Swift package for building LLM/VLM tools and apps with MLX Swift.
- It supports LLM and VLM model families.
- Recent releases mention raw token streaming and multiple tool call handling.
- Integration choices for tokenizers/downloaders are explicit dependency decisions.

Required work:

- Verify the exact current APIs for token streaming, `ChatSession`, tool specs, tool dispatch, and tool output injection in the version SwiftAgent vendors.
- Normalize token streaming into response text deltas.
- Normalize local tool dispatch into tool call/tool output transcript entries.
- Preserve VLM image prompt segments when supported.
- Gate MLX dependencies so the base SwiftAgent package does not require MLX.
- Add tests around local token streaming and tool call transcript updates where deterministic fixtures are possible.

### CoreMLLanguageModel

Primary docs:

- https://developer.apple.com/documentation/CoreML
- https://developer.apple.com/documentation/CoreML/integrating-a-core-ml-model-into-your-app

Observed capability from docs:

- Core ML is a general model inference framework for predictions, not a language-model agent protocol.
- Streaming, tool calling, transcript management, and reasoning are not native Core ML concepts.

Required work:

- Treat CoreMLLanguageModel as a specialized local backend with limited capabilities unless the vendored model wrapper implements token-level generation.
- Make unsupported agent features explicit in provider capabilities.
- Do not pretend Core ML supports tool-call streaming unless the specific local model wrapper implements it.

### SystemLanguageModel / Apple Foundation Models

Primary docs:

- https://developer.apple.com/videos/play/wwdc2025/286/

Observed capability from docs:

- Apple's Foundation Models framework includes guided generation, snapshot streaming, tool calling, and stateful sessions.
- Snapshot streaming is oriented around partially generated `Generable` values rather than raw token deltas.

Required work:

- Keep SystemLanguageModel / Apple Foundation Models support.
- Adapt snapshot streaming into the main transcript-first update model.
- Preserve tool calls and structured output in transcript entries.
- Mark any unavailable lower-level details, such as raw token deltas or provider token usage, as unsupported capabilities.

### Llama.cpp / LlamaLanguageModel

Primary docs:

- https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md

Observed capability from docs:

- `llama-server` exposes OpenAI-compatible completions/chat endpoints.
- Streaming mode is supported for completions.
- Multimodal input is supported when the model supports it.
- The server exposes internal built-in tools for its Web UI, but downstream apps are told not to use that internal `/tools` endpoint.
- Token counting is available on Anthropic-compatible messages endpoints.

Required work:

- Prefer OpenAI-compatible chat/completions endpoints for remote llama.cpp server integration.
- Verify current tool-call streaming behavior for the target llama.cpp version instead of assuming parity with OpenAI.
- Normalize streamed text into response entries.
- Represent tool support as model/server capability dependent.
- Keep direct in-process Llama dependencies optional.

## Capability Model Candidate

A provider capability model should use the hybrid direction from the inspected SDKs:

- Conduit-style separation between model, provider, and runtime capabilities.
- Swarm-style `OptionSet` flags for simple checks and protocol inference.
- Swift AI SDK-style rich streaming event enum for provider-to-session streaming.

Candidate shape:

```swift
public struct LanguageModelCapabilities: Sendable, Equatable {
  public var model: ModelCapabilities
  public var provider: ProviderCapabilities
  public var runtime: RuntimeCapabilities?
}

public struct ProviderCapabilities: OptionSet, Sendable, Hashable {
  public let rawValue: Int

  public static let textStreaming = Self(rawValue: 1 << 0)
  public static let structuredOutputs = Self(rawValue: 1 << 1)
  public static let structuredStreaming = Self(rawValue: 1 << 2)
  public static let toolCalling = Self(rawValue: 1 << 3)
  public static let toolCallStreaming = Self(rawValue: 1 << 4)
  public static let parallelToolCalls = Self(rawValue: 1 << 5)
  public static let imageInput = Self(rawValue: 1 << 6)
  public static let reasoningSummaries = Self(rawValue: 1 << 7)
  public static let encryptedReasoningContinuity = Self(rawValue: 1 << 8)
  public static let tokenUsage = Self(rawValue: 1 << 9)
  public static let streamingTokenUsage = Self(rawValue: 1 << 10)
}
```

The stream should use rich events instead of plain text chunks:

```swift
public enum LanguageModelStreamEvent: Sendable {
  case textStart(id: String)
  case textDelta(id: String, delta: String)
  case textEnd(id: String)

  case reasoningStart(id: String)
  case reasoningDelta(id: String, delta: String)
  case reasoningEnd(id: String)

  case toolInputStart(id: String, toolName: String)
  case toolInputDelta(id: String, delta: String)
  case toolInputEnd(id: String)

  case toolCall(ToolCall)
  case toolResult(ToolResult)
  case responseMetadata(ResponseMetadata)
  case usage(TokenUsage)
  case finish(FinishReason)
}
```

Older boolean-style sketches such as the following should be treated as implementation notes, not the preferred shape:

```swift
public struct BooleanCapabilitySketch: Sendable, Equatable {
  public var supportsTextStreaming: Bool
  public var supportsStructuredStreaming: Bool
  public var supportsToolCalling: Bool
  public var supportsToolCallStreaming: Bool
  public var supportsParallelToolCalls: Bool
  public var supportsImageInput: Bool
  public var supportsReasoningSummaries: Bool
  public var supportsEncryptedReasoningContinuity: Bool
  public var supportsTokenUsage: Bool
  public var supportsStreamingTokenUsage: Bool
}
```

Use capabilities for validation, fallback behavior, test expectations, and UI affordances. Use stream events to represent what is happening in a specific run. Do not use capabilities to excuse missing work for providers that can support agent-grade streaming.

## Test Requirements

Each provider should have tests for the features it claims to support:

- text streaming emits incremental response transcript updates
- final snapshot matches final transcript state
- tool call streaming emits tool call entries before tool execution
- tool output entries are visible before the final response
- reasoning entries stream separately from assistant text
- token usage is surfaced outside transcript entries
- unsupported capabilities fail clearly or degrade explicitly
