# Provider Capability and Streaming Reference

## Purpose

This document distills the provider capability and streaming patterns inspected from the attached Conduit, Swarm, and Swift AI SDK repositories. It exists so future SwiftAgent implementation work does not need to re-read those full codebases just to recover the architectural takeaways.

Original local references used while creating this document:

- `.context/attachments/Conduit-main.zip`
- `.context/attachments/Swarm-main.zip`
- `.context/attachments/swift-ai-sdk-main.zip`

The sketches below are adapted to SwiftAgent's intended architecture. They are not intended as direct copies.

## Conduit

### Pattern: Separate Capability Layers

Conduit separates capability concepts into different layers:

- model capabilities
- provider/API capabilities
- runtime/backend capabilities

This distinction is useful because these questions are different:

- Can this model understand images?
- Can this provider API stream tool calls?
- Can this local runtime use KV cache quantization?

### Relevant Type Sketches

Conduit's model-level capability shape is roughly:

```swift
public struct ModelCapabilities: Sendable, Hashable {
  public let supportsVision: Bool
  public let supportsTextGeneration: Bool
  public let supportsEmbeddings: Bool
  public let architectureType: ArchitectureType?
  public let contextWindowSize: Int?
}
```

Conduit's provider/runtime layer uses feature identities with associated details:

```swift
public enum ProviderRuntimeFeature: String, Sendable, Codable, CaseIterable {
  case kvQuantization
  case attentionSinks
  case kvSwap
  case incrementalPrefill
  case speculativeScheduling
}

public struct ProviderRuntimeFeatureCapability: Sendable, Hashable, Codable {
  public var isSupported: Bool
  public var supportedBits: [Int]
  public var maxSinkTokens: Int?
  public var maxDraftStreams: Int?
  public var maxDraftAheadTokens: Int?
  public var maxIncrementalPrefillTokens: Int?
  public var supportsVerifierRollback: Bool
  public var reasonUnavailable: String?
}
```

Conduit also uses provider-specific `OptionSet` capabilities for OpenAI-compatible providers:

```swift
public struct OpenAICapabilities: OptionSet, Sendable, Hashable {
  public let rawValue: Int

  public static let textGeneration = Self(rawValue: 1 << 0)
  public static let streaming = Self(rawValue: 1 << 1)
  public static let embeddings = Self(rawValue: 1 << 2)
  public static let imageGeneration = Self(rawValue: 1 << 3)
  public static let transcription = Self(rawValue: 1 << 4)
  public static let functionCalling = Self(rawValue: 1 << 5)
  public static let jsonMode = Self(rawValue: 1 << 6)
  public static let vision = Self(rawValue: 1 << 7)
  public static let textToSpeech = Self(rawValue: 1 << 8)
  public static let parallelFunctionCalling = Self(rawValue: 1 << 9)
  public static let structuredOutputs = Self(rawValue: 1 << 10)
}
```

### What SwiftAgent Should Copy Conceptually

- Separate model, provider, and runtime capability questions.
- Track unavailable reasons when a runtime feature is unsupported.
- Use model architecture/context metadata for local providers where it affects behavior.
- Use compact `OptionSet` flags for common provider checks.
- Treat tool execution as a policy-driven actor/service, including retry behavior and missing-tool behavior.
- Capture provider response metadata such as rate-limit state and retry-after hints.

### What SwiftAgent Should Not Copy

- Do not create provider-specific capability types as the only public capability model. SwiftAgent needs a normalized capability view across providers.
- Do not overfit to low-level runtime features in the base session engine. Runtime features should be available for local-provider tuning but should not clutter normal cloud-provider workflows.
- Do not let static capabilities replace streaming events. Capabilities describe what may happen; stream events describe what is happening.

## Swarm

### Pattern: OptionSet Capabilities and Protocol Inference

Swarm uses a small `OptionSet` for provider capabilities and infers some capabilities from protocol conformance.

This is a useful pattern because simple checks stay ergonomic:

```swift
if capabilities.contains(.streamingToolCalls) {
  // Render live tool arguments.
}
```

And providers do not need to manually report every flag when protocol conformance already proves support.

### Relevant Type Sketches

Swarm's provider capability shape is roughly:

```swift
public struct InferenceProviderCapabilities: OptionSet, Sendable, Hashable {
  public let rawValue: Int

  public static let conversationMessages = Self(rawValue: 1 << 0)
  public static let nativeToolCalling = Self(rawValue: 1 << 1)
  public static let streamingToolCalls = Self(rawValue: 1 << 2)
  public static let responseContinuation = Self(rawValue: 1 << 3)
  public static let structuredOutputs = Self(rawValue: 1 << 4)
}
```

Swarm infers capabilities from provider protocols:

```swift
public extension InferenceProviderCapabilities {
  static func inferred(from provider: any InferenceProvider) -> Self {
    var capabilities: Self = []

    if provider is any ConversationInferenceProvider {
      capabilities.insert(.conversationMessages)
    }

    if provider is any ToolCallStreamingInferenceProvider {
      capabilities.insert(.streamingToolCalls)
    }

    if provider is any StructuredOutputInferenceProvider {
      capabilities.insert(.structuredOutputs)
    }

    return capabilities
  }
}
```

It also allows explicit provider reporting:

```swift
public protocol CapabilityReportingInferenceProvider: InferenceProvider {
  var capabilities: InferenceProviderCapabilities { get }
}
```

Then capability resolution can prefer explicit reporting and fall back to inference.

### Streaming Tool Call Updates

Swarm has a provider-originated streaming update enum for live tool-call behavior:

```swift
public enum InferenceStreamUpdate: Sendable, Equatable {
  case outputChunk(String)
  case toolCallPartial(PartialToolCallUpdate)
  case toolCallsCompleted([ParsedToolCall])
  case usage(TokenUsage)
}
```

This is smaller than the SwiftAgent target shape, but the important idea is that tool call assembly can stream separately from assistant text.

### SwiftAgent Adaptation

SwiftAgent should use:

- `OptionSet` flags for common provider checks.
- protocol inference for capabilities implied by provider protocol conformance.
- explicit reporting for model/provider-specific differences.
- streaming tool-call updates as first-class events, not text parsing side effects.
- transcript replay/diff helpers for deterministic fixture review.
- stable transcript/session state that does not prevent future conversation branching, without implementing branching during the merge.

SwiftAgent should go further than Swarm by representing reasoning, metadata, structured output, finish status, and raw provider diagnostics in the normalized event stream.

## Swift AI SDK

### Pattern: Rich Streaming Event Enum

Swift AI SDK's strongest relevant pattern is the rich typed stream part enum. It avoids reducing streaming to text chunks and instead models every meaningful provider event as a typed part.

### Relevant Stream Event Shape

The SDK's `LanguageModelV3StreamPart` includes categories like:

```swift
public enum LanguageModelV3StreamPart {
  case textStart(id: String, providerMetadata: ProviderMetadata?)
  case textDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)
  case textEnd(id: String, providerMetadata: ProviderMetadata?)

  case reasoningStart(id: String, providerMetadata: ProviderMetadata?)
  case reasoningDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)
  case reasoningEnd(id: String, providerMetadata: ProviderMetadata?)

  case toolInputStart(
    id: String,
    toolName: String,
    providerMetadata: ProviderMetadata?,
    providerExecuted: Bool?,
    dynamic: Bool?,
    title: String?
  )
  case toolInputDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)
  case toolInputEnd(id: String, providerMetadata: ProviderMetadata?)

  case toolCall(ToolCall)
  case toolResult(ToolResult)
  case file(File)
  case source(Source)
  case streamStart(warnings: [Warning])
  case responseMetadata(id: String?, modelId: String?, timestamp: Date?)
  case finish(finishReason: FinishReason, usage: Usage, providerMetadata: ProviderMetadata?)
  case raw(rawValue: JSONValue)
  case error(error: JSONValue)
}
```

### Warnings and Unsupported Functionality

Swift AI SDK also models unsupported behavior explicitly:

- warnings for unsupported settings/tools/features
- `UnsupportedFunctionalityError`
- provider-specific checks that add warnings or throw when prompt content cannot be represented by the provider

This is useful because not every provider rejects unsupported settings at the same layer. Some settings can degrade with a warning; others must fail early.

SwiftAgent should adopt this idea in Swift-native form only where it improves the developer experience. This should not become a TypeScript-port artifact. For this repo, warnings are useful for provider option degradation, unsupported optional settings, unsupported provider-defined tools, and fallback paths that still produce a valid result.

### What SwiftAgent Should Copy Conceptually

- Use typed stream events for text, reasoning, tool input deltas, completed tool calls/results, metadata, finish, raw chunks, and errors.
- Preserve provider metadata without making it the primary public API.
- Surface unsupported functionality intentionally as warnings or typed errors.
- Include finish usage as a stream event when providers report usage at the end.
- Preserve typed provider-specific custom options from AnyLanguageModel's `GenerationOptions` rather than adopting untyped provider option dictionaries as the primary API.

### What SwiftAgent Should Not Copy

- Do not make provider metadata dominate SwiftAgent's transcript model.
- Do not use warnings as a substitute for capability checks when the unsupported behavior is knowable before the request.
- Do not expose low-level provider stream events directly as the only user-facing stream; SwiftAgent should reduce them into transcript updates and snapshots.

## SwiftAgent Proposed Design

### Capability Model

SwiftAgent should use a hybrid capability model:

```swift
public struct LanguageModelCapabilities: Sendable, Equatable {
  public var model: ModelCapabilities
  public var provider: ProviderCapabilities
  public var runtime: RuntimeCapabilities?
}
```

Model capabilities answer questions about the selected model:

```swift
public struct ModelCapabilities: Sendable, Equatable {
  public var supportsTextGeneration: Bool
  public var supportsImageInput: Bool
  public var supportsAudioInput: Bool
  public var supportsEmbeddings: Bool
  public var supportsReasoning: Bool
  public var contextWindowTokens: Int?
  public var maximumOutputTokens: Int?
  public var architecture: String?
}
```

Provider capabilities answer questions about the API/provider path:

```swift
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
  public static let responseContinuation = Self(rawValue: 1 << 11)
}
```

Runtime capabilities answer questions about local execution backends:

```swift
public struct RuntimeCapabilities: Sendable, Equatable {
  public var supportsKVQuantization: Bool
  public var supportsSpeculativeDecoding: Bool
  public var supportsIncrementalPrefill: Bool
  public var supportsModelCache: Bool
  public var unavailableReasons: [String: String]
}
```

### Protocol Inference

SwiftAgent can infer provider flags from protocol conformance:

```swift
public protocol CapabilityReportingLanguageModel: LanguageModel {
  var capabilities: LanguageModelCapabilities { get }
}

public protocol EventStreamingLanguageModel: LanguageModel {
  func streamEvents(...) -> AsyncThrowingStream<LanguageModelStreamEvent, any Error>
}

public protocol StreamingToolCallLanguageModel: EventStreamingLanguageModel {
  // Marker protocol for models that can emit tool input deltas/completed calls.
}

public protocol StructuredOutputLanguageModel: LanguageModel {}

public extension ProviderCapabilities {
  static func inferred(from model: any LanguageModel) -> Self {
    var capabilities: Self = []

    if model is any EventStreamingLanguageModel {
      capabilities.insert(.textStreaming)
    }

    if model is any StreamingToolCallLanguageModel {
      capabilities.insert(.toolCallStreaming)
    }

    if model is any StructuredOutputLanguageModel {
      capabilities.insert(.structuredOutputs)
    }

    return capabilities
  }
}
```

Explicit reporting should win over inference when a provider knows more than protocol conformance can express, especially for model-specific differences.

### Rich Stream Event

Provider implementations should normalize native provider streams into a rich SwiftAgent event enum:

```swift
public enum LanguageModelStreamEvent: Sendable {
  case streamStarted(warnings: [LanguageModelWarning])

  case textStart(id: String)
  case textDelta(id: String, delta: String)
  case textEnd(id: String)

  case structuredStart(id: String, typeName: String)
  case structuredDelta(id: String, delta: GeneratedContent)
  case structuredEnd(id: String)

  case reasoningStart(id: String)
  case reasoningDelta(id: String, delta: String)
  case reasoningEnd(id: String, encryptedReasoning: String?)

  case toolInputStart(id: String, toolName: String)
  case toolInputDelta(id: String, delta: String)
  case toolInputEnd(id: String)
  case toolCall(ToolCall)
  case toolResult(ToolResult)

  case responseMetadata(ResponseMetadata)
  case usage(TokenUsage)
  case finished(FinishReason)
  case raw(JSONValue)
  case failed(LanguageModelStreamError)
}
```

The session engine should reduce these events into:

```swift
public enum LanguageModelUpdate {
  case transcript(Transcript.Entry)
  case tokenUsage(TokenUsage)
}
```

Then public UI snapshots should be derived from transcript/token state.

### Relationship Between Capabilities and Events

Capabilities answer what can happen:

```swift
capabilities.provider.contains(.toolCallStreaming)
```

Events answer what is happening:

```swift
case .toolInputDelta(id: "call_123", delta: "{\"city\":\"Lis")
```

The two should work together:

- capabilities validate unsupported requests before sending them
- events drive transcript updates during a run
- tests assert that providers emit the events promised by their capabilities
- UI can use capabilities for affordances and events/snapshots for live state

Capabilities must not become an excuse for content-only streaming where providers can support agent-grade streaming.

### Tool Execution Policy

Tool execution should be configured at the session level rather than hidden inside provider code:

```swift
public struct ToolExecutionOptions: Sendable, Equatable {
  public var allowsParallelExecution: Bool
  public var retryPolicy: ToolRetryPolicy
  public var missingToolPolicy: MissingToolPolicy
  public var failurePolicy: ToolFailurePolicy
  public var requiresApproval: Bool
}

public enum ToolRetryPolicy: Sendable, Equatable {
  case none
  case retryableErrors(maxAttempts: Int)
  case allNonCancellationErrors(maxAttempts: Int)
}

public enum MissingToolPolicy: Sendable, Equatable {
  case throwError
  case emitToolOutput
}

public enum ToolFailurePolicy: Sendable, Equatable {
  case throwError
  case emitToolOutput
  case askModelToRecover
}
```

This keeps provider adapters focused on model I/O while the session engine owns agent behavior.

### Provider Response Metadata

Provider response metadata should be normalized and surfaced with responses/snapshots:

```swift
public struct ProviderResponseMetadata: Sendable, Equatable {
  public var requestID: UUID?
  public var providerRequestID: String?
  public var modelID: String?
  public var rateLimit: RateLimitInfo?
  public var retryAfter: Duration?
  public var warnings: [LanguageModelWarning]
}

public struct RateLimitInfo: Sendable, Equatable {
  public var limitRequests: Int?
  public var remainingRequests: Int?
  public var resetRequests: Date?
  public var limitTokens: Int?
  public var remainingTokens: Int?
  public var resetTokens: Date?
}
```

SwiftAgent already has HTTP request IDs and replay recording internally. The merged model layer should expose the useful, normalized metadata at the model/session level.

### Logging

SwiftAgent's existing logging direction should win over AnyLanguageModel's lighter provider-local logging.

Keep:

- `AgentLog`-style lifecycle logs for runs, steps, tools, reasoning, structured output, and token usage.
- `NetworkLog`-style opt-in raw HTTP logging.
- replay-recorder-friendly request/response capture.

Add:

- logging of normalized stream events during debugging.
- logging of provider warnings and metadata.
- redaction hooks for API keys, auth headers, and sensitive tool outputs.

Avoid:

- noisy provider-specific logging APIs as the primary user-facing logging story.
- logging raw reasoning/encrypted reasoning without an explicit debug setting.

### Transcript Replay and Diff

SwiftAgent transcripts are already `Codable`, `Equatable`, and stable-ID based, but replay work would benefit from explicit fixture support:

```swift
public enum TranscriptSchemaVersion: String, Codable, Sendable {
  case v1
}

public struct Transcript: Sendable, Equatable, Codable {
  public var schemaVersion: TranscriptSchemaVersion
  public var entries: [Entry]
}

public struct TranscriptDiff: Sendable, Equatable {
  public var path: String
  public var expected: String
  public var actual: String
}

public extension Transcript {
  func firstDiff(comparedTo other: Transcript) -> TranscriptDiff?
}
```

Practical uses:

- fixture review when provider payload formats change.
- regression tests for streaming transcript assembly.
- migration tests while merging SwiftAgent and AnyLanguageModel transcript models.
- stable debugging output when a provider emits events in a surprising order.

### Structured Output Source

Structured output should record the mechanism used to produce it:

```swift
public enum StructuredOutputSource: String, Sendable, Codable {
  case providerNative
  case promptFallback
  case constrainedDecoder
}
```

Add source tracking either to structured transcript segments or response metadata:

```swift
public struct StructuredSegment: Sendable, Identifiable, Equatable, Codable {
  public var id: String
  public var typeName: String
  public var content: GeneratedContent
  public var source: StructuredOutputSource
}
```

This makes debugging and tests clearer because native provider enforcement, prompt-based JSON parsing, and local constrained decoding have different reliability and failure modes.
