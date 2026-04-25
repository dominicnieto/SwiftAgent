# Dependency Migration Plan

## Purpose

Define how AnyLanguageModel package dependencies should move into SwiftAgent during the no-bridge merge.

This is a dependency plan only. It does not choose canonical core types, does not merge providers, and does not require editing SwiftAgent's root `Package.swift` during Phase 1.

## Current SwiftAgent Dependencies

SwiftAgent currently depends on:

- `swift-syntax`: macro implementation.
- MacPaw `OpenAI`: current OpenAI SDK adapter path.
- `SwiftAnthropic`: current Anthropic SDK adapter path.
- `EventSource`: SSE parsing.
- `swift-macro-testing`: macro tests.

The merge should eventually remove MacPaw `OpenAI` and `SwiftAnthropic` once direct providers reach replay parity.

## Current AnyLanguageModel Dependencies

AnyLanguageModel currently depends on:

- `swift-syntax`: macros.
- `EventSource`: SSE parsing, with AsyncHTTPClient trait support.
- `JSONSchema`: schema construction/conversion.
- `PartialJSONDecoder`: partial structured-output decoding during streaming.
- `async-http-client`: optional transport through SwiftPM trait `AsyncHTTPClient`.
- `swift-transformers`: CoreML local provider support.
- `mlx-swift-lm`: MLX local provider support.
- `llama.swift`: Llama local provider support.

AnyLanguageModel traits:

- `CoreML`
- `MLX`
- `Llama`
- `AsyncHTTPClient`

## Migration Principles

- Phase 1 copies AnyLanguageModel first and builds the copied package in place.
- Do not add all AnyLanguageModel dependencies to SwiftAgent's root manifest just because the copied repo has them.
- Add dependencies to SwiftAgent only when a phase starts compiling moved code through SwiftAgent targets.
- Do not remove dependencies from either SwiftAgent's package or the copied AnyLanguageModel package without explicit approval.
- Any dependency removal proposal must list the dependency, current users, replacement path, affected targets/products, and test/build evidence.
- Keep the base `SwiftAgent` product lightweight.
- Heavy local runtime dependencies should be isolated behind optional provider targets/products.
- SwiftPM traits are allowed, but use separate targets/products when that is clearer for users and CI.
- Existing SwiftAgent transport, replay, and logging should win over importing a second long-term transport stack.

## Dependency Classification

| Dependency | Initial Phase 1 Action | Likely Final Placement | Notes |
| --- | --- | --- | --- |
| `swift-syntax` | No root manifest change needed | Base macro dependency | Both repos already use it. Reconcile version ranges when macro code is merged. |
| `EventSource` | No root manifest change needed | Base dependency if SSE helper remains useful | SwiftAgent already depends on `EventSource` `1.2.0`; ALM uses `1.3.0`. Reconcile during provider migration. |
| `JSONSchema` | Do not add until schema code is moved | Probably base `SwiftAgent` or internal replacement | Needed if ALM schema builders/converters remain. Decide in Phase 2 when canonical schema code is chosen. |
| `PartialJSONDecoder` | Do not add until streaming structured output code is moved | Probably base `SwiftAgent` if used by core streaming | Useful for partial JSON snapshots. Add when Phase 3/4 needs it, not during copy-only Phase 1. |
| `async-http-client` | Keep inside copied ALM package only | Optional transport support or removed | SwiftAgent has `HTTPClient`, `URLSessionHTTPClient`, `HTTPReplayRecorder`, `NetworkLog`, and `AgentLog`. Prefer adapting ALM providers to SwiftAgent transport before making AHC part of the public package shape. |
| `swift-transformers` | Keep inside copied ALM package only | Optional `SwiftAgentCoreML` target/product if retained | Should not affect base builds. CoreML provider work belongs after core/provider parity. |
| `mlx-swift-lm` | Keep inside copied ALM package only | Optional `SwiftAgentMLX` target/product | Do not make base `SwiftAgent` depend on MLX. |
| `llama.swift` | Keep inside copied ALM package only | Optional `SwiftAgentLlama` target/product | Do not make base `SwiftAgent` depend on Llama. |
| MacPaw `OpenAI` | Keep until direct OpenAI parity | Remove after Phase 4 parity | Current SwiftAgent provider tests depend on this SDK path. Remove only after replay parity proves replacement. |
| `SwiftAnthropic` | Keep until direct Anthropic parity | Remove after Phase 5 parity | Current SwiftAgent provider tests depend on this SDK path. Remove only after replay parity proves replacement. |
| `swift-macro-testing` | Keep | Test-only dependency | No ALM conflict. |

## Phase Guidance

### Phase 1: Copy Source

Allowed:

- Copy `/Users/dominicnieto/Desktop/AnyLanguageModel` into `External/AnyLanguageModel`.
- Build the copied package from `External/AnyLanguageModel`.
- Let the copied package keep its own `Package.swift` and dependency graph.

Avoid:

- Adding ALM dependencies to SwiftAgent root `Package.swift`.
- Wiring SwiftAgent targets to copied ALM targets.
- Pruning dependency declarations.
- Replacing SwiftAgent transport, logging, replay, or provider SDKs.

Phase 1 exit should report the copied package build command/result and any dependency resolution failures.

Dependency removal approval: Phase 1 should not remove dependencies from either package. If a dependency appears obsolete during copy/build, document it only and wait for a later approved phase.

### Phase 2: Canonical Core Types

When core ALM files start moving into `Sources/SwiftAgent`, decide whether `JSONSchema` and `PartialJSONDecoder` become base dependencies.

Do not add MLX, Llama, CoreML, or AsyncHTTPClient to the base target in this phase.

Expected dependency decisions:

- Reconcile `swift-syntax` macro dependency shape.
- Decide whether `JSONSchema` is a real base dependency or whether existing SwiftAgent schema conversion code replaces it.
- Decide whether `PartialJSONDecoder` is needed for canonical streaming structured output.

Dependency removal approval: Before removing any dependency from either package, produce the removal proposal described in "Migration Principles" and wait for explicit approval.

### Phase 3: Transcript and Streaming

Add `PartialJSONDecoder` only if the merged streaming engine uses ALM's partial structured decoding approach.

Keep transport and replay aligned with SwiftAgent:

- `HTTPClient`
- `URLSessionHTTPClient`
- `HTTPReplayRecorder`
- `NetworkLog`
- `AgentLog`

If AsyncHTTPClient support survives, keep it behind an explicit optional target/trait and make sure replay recording still works without it.

Dependency removal approval: Before removing or disabling any transport/streaming dependency from either package, produce the removal proposal described in "Migration Principles" and wait for explicit approval.

### Phase 4: OpenAI Provider

Direct OpenAI provider code may require:

- `EventSource`
- `JSONSchema`
- `PartialJSONDecoder`

It should not require MacPaw `OpenAI` once parity is proven.

Remove MacPaw `OpenAI` only after:

- OpenAI text tests pass through the direct provider.
- OpenAI structured-output tests pass through the direct provider.
- OpenAI tool-call tests pass through the direct provider.
- OpenAI streaming tests emit transcript-first updates.
- AgentRecorder can record OpenAI fixtures through the merged provider path.

Dependency removal approval: Meeting these gates is not enough to remove MacPaw `OpenAI`; still present the removal proposal and wait for explicit approval.

### Phase 5: Anthropic Provider

Direct Anthropic provider code may require:

- `EventSource`
- `JSONSchema`
- `PartialJSONDecoder`

It should not require `SwiftAnthropic` once parity is proven.

Remove `SwiftAnthropic` only after:

- Anthropic text tests pass through the direct provider.
- Anthropic structured-output tests pass through the direct provider.
- Anthropic tool-call tests pass through the direct provider.
- Anthropic streaming thinking/reasoning tests pass.
- AgentRecorder can record Anthropic fixtures through the merged provider path.

Dependency removal approval: Meeting these gates is not enough to remove `SwiftAnthropic`; still present the removal proposal and wait for explicit approval.

### Phase 6: Other Providers

Provider dependency placement:

- `GeminiLanguageModel`: base provider candidate if it only uses lightweight HTTP/SSE dependencies.
- `OllamaLanguageModel`: base provider candidate if it only uses lightweight HTTP/SSE dependencies.
- `SystemLanguageModel`: availability-gated Apple FoundationModels integration; can live in base if conditional imports do not affect unsupported platforms.
- `CoreMLLanguageModel`: optional `SwiftAgentCoreML` target/product.
- `MLXLanguageModel`: optional `SwiftAgentMLX` target/product.
- `LlamaLanguageModel`: optional `SwiftAgentLlama` target/product.

Dependency removal approval: Before dropping any optional provider dependency or copied-provider dependency, produce the removal proposal described in "Migration Principles" and wait for explicit approval.

## Package Shape Target

Base product:

```swift
.library(name: "SwiftAgent", targets: ["SwiftAgent"])
```

Optional local provider products:

```swift
.library(name: "SwiftAgentMLX", targets: ["SwiftAgentMLX"])
.library(name: "SwiftAgentLlama", targets: ["SwiftAgentLlama"])
.library(name: "SwiftAgentCoreML", targets: ["SwiftAgentCoreML"])
```

Use traits only where they make dependency conditions clearer than separate products.

## Open Questions For Implementation Phases

- Should `JSONSchema` remain a public dependency, or can SwiftAgent's existing schema conversion cover the merged API?
- Should `PartialJSONDecoder` be part of base streaming support, or isolated to structured-output internals?
- Should AsyncHTTPClient support survive as an optional transport path after providers use SwiftAgent replay/logging?
- Should `SystemLanguageModel` live in the base target with conditional import, or in a platform-specific optional target?
- Which local providers are worth preserving before OpenAI/Anthropic/Gemini/Ollama parity is complete?
