# Dependency Migration Plan

## Purpose

Define how AnyLanguageModel package dependencies should move into SwiftAgent during the no-bridge merge.

This is a dependency plan only. It does not choose main core types, does not merge providers, and does not require editing SwiftAgent's root `Package.swift` during Phase 1.

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
- Do not hand-roll replacement JSON/schema infrastructure just to avoid an otherwise appropriate dependency. In merged Phase 2, `JSONSchema` and `PartialJSONDecoder` additions are approved when moved AnyLanguageModel code naturally depends on them; prefer preserving the dependency-backed implementation and record current users, affected targets, and validation evidence instead of rewriting large portions of ALM logic.

## Dependency Classification

| Dependency | Initial Phase 1 Action | Likely Final Placement | Notes |
| --- | --- | --- | --- |
| `swift-syntax` | No root manifest change needed | Base macro dependency | Both repos already use it. Reconcile version ranges when macro code is merged. |
| `EventSource` | No root manifest change needed | Base dependency if SSE helper remains useful | SwiftAgent already depends on `EventSource` `1.2.0`; ALM uses `1.3.0`. Reconcile during provider migration. |
| `JSONSchema` | Do not add during copy-only Phase 1 | Approved in merged Phase 2 when ALM `GenerationOptions`, `JSONValue`, direct providers, or provider-neutral schema conversion move into SwiftAgent | ALM uses `JSONSchema.JSONValue` heavily for custom options, provider request bodies, tool arguments, and schema conversion. Prefer adding it when needed over rewriting ALM JSON/schema logic. It does not replace SwiftAgent's `GenerationSchema`, stable encoding, transcript/replay, or provider-specific normalization requirements. |
| `PartialJSONDecoder` | Do not add during copy-only Phase 1 | Approved in merged Phase 2 when structured streaming / partial snapshots move into SwiftAgent | Useful for partial structured-output decoding. It does not replace transcript-first streaming assembly, tool-call event handling, or provider stream parsing. Prefer adding it if the merged streaming implementation uses ALM's partial decoding path. |
| `async-http-client` | Keep out of base builds | Optional SwiftPM trait on `SwiftAgent` | SwiftAgent has `HTTPClient`, `URLSessionHTTPClient`, `HTTPReplayRecorder`, `NetworkLog`, and `AgentLog`. ALM providers were adapted to SwiftAgent transport; AHC is available only when the `AsyncHTTPClient` trait is enabled. |
| `swift-transformers` | Keep inside copied ALM package only | Optional `SwiftAgentCoreML` target/product if retained | Should not affect base builds. CoreML provider work belongs after core/provider parity. |
| `mlx-swift-lm` | Keep inside copied ALM package only | Optional `SwiftAgentMLX` target/product | Do not make base `SwiftAgent` depend on MLX. |
| `llama.swift` | Keep inside copied ALM package only | Optional `SwiftAgentLlama` target/product | Do not make base `SwiftAgent` depend on Llama. |
| MacPaw `OpenAI` | Removed after approval | Removed in merged Phase 2 | Direct provider replay parity was proven and the user explicitly approved removal on April 25, 2026. |
| `SwiftAnthropic` | Removed after approval | Removed in merged Phase 2 | Direct provider replay parity was proven and the user explicitly approved removal on April 25, 2026. |
| `swift-macro-testing` | Keep | Test-only dependency | No ALM conflict. |

## Phase Guidance

The original split between Phase 2 main types, Phase 3 transcript/streaming, Phase 4 OpenAI,
and Phase 5 Anthropic is superseded. These areas now move together in Phase 2 Core Model Stack
Merge because their dependencies and types are architecturally coupled.

Dependency decisions should support whole-feature movement. Do not rewrite ALM JSON/schema,
streaming, or provider code to avoid a dependency, and do not introduce interim protocols or
placeholder types just to keep a dependency or related type out of the current phase.

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

### Phase 2: Core Model Stack Merge

When ALM core, session, transcript, streaming, and direct provider files move into `Sources/SwiftAgent`, move their real dependency-backed implementation unless there is a product reason to redesign it.

Do not add MLX, Llama, CoreML, or AsyncHTTPClient to the base target in this phase.

Approved dependency additions for this phase:

- Add `JSONSchema` to the root package when moving `GenerationOptions`, `JSONValue`, direct provider request builders, provider-neutral schema conversion, or provider custom option payloads.
- Add `PartialJSONDecoder` to the root package when moving structured streaming or partial snapshot decoding.

Expected dependency work:

- Reconcile `swift-syntax` macro dependency shape.
- Reconcile `EventSource` versions while moving direct providers.
- Keep SwiftAgent `HTTPClient`, `URLSessionHTTPClient`, `HTTPReplayRecorder`, `NetworkLog`, and `AgentLog` as the long-term transport/replay/logging direction.
- Adapt ALM provider transport to SwiftAgent replay/logging rather than introducing a second long-term transport stack.

Dependency removal approval: Before removing any dependency from either package, produce the removal proposal described in "Migration Principles" and wait for explicit approval.

OpenAI and Anthropic direct provider work is part of this same phase.

Direct OpenAI provider code may require:

- `EventSource`
- `JSONSchema`
- `PartialJSONDecoder`

It no longer requires MacPaw `OpenAI`.

Remove MacPaw `OpenAI` only after:

- OpenAI text tests pass through the direct provider.
- OpenAI structured-output tests pass through the direct provider.
- OpenAI tool-call tests pass through the direct provider.
- OpenAI streaming tests emit transcript-first updates.
- AgentRecorder can record OpenAI fixtures through the merged provider path.

Dependency removal approval: granted on April 25, 2026; removal was implemented after replay parity.

Direct Anthropic provider code may require:

- `EventSource`
- `JSONSchema`
- `PartialJSONDecoder`

It no longer requires `SwiftAnthropic`.

Remove `SwiftAnthropic` only after:

- Anthropic text tests pass through the direct provider.
- Anthropic structured-output tests pass through the direct provider.
- Anthropic tool-call tests pass through the direct provider.
- Anthropic streaming thinking/reasoning tests pass.
- AgentRecorder can record Anthropic fixtures through the merged provider path.

Dependency removal approval: granted on April 25, 2026; removal was implemented after replay parity.

### Phase 3: Other Providers

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

- Should `JSONSchema` remain visible through public API surfaces beyond the `JSONValue` typealias, or stay an implementation dependency where possible?
- Should `PartialJSONDecoder` be part of base streaming support, or isolated to structured-output internals?
- AsyncHTTPClient support survives as an optional SwiftPM trait-backed transport path after providers use SwiftAgent replay/logging.
- Should `SystemLanguageModel` live in the base target with conditional import, or in a platform-specific optional target?
- Which local providers are worth preserving before OpenAI/Anthropic/Gemini/Ollama parity is complete?
