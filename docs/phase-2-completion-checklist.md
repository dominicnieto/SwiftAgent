# Phase 2 Core Model Stack Merge Checklist

## Status

Status: complete. Main model/session/provider/recorder work, dependency removals approved on April 25, 2026, legacy provider-session product cleanup, and final validation are implemented in the current branch.

This checklist supersedes the earlier narrow Phase 2 checklist. The old plan separated main types, transcript/streaming, OpenAI provider replacement, and Anthropic provider replacement into separate phases. That split is no longer the working model because it encourages temporary protocols and compatibility scaffolding.

Phase 2 now means the full core model stack merge:

- main core primitives and options
- `LanguageModel`
- `LanguageModelSession`
- transcript-first streaming
- tool execution policy
- direct OpenAI provider parity
- direct Anthropic provider parity
- AgentRecorder/examples/docs migration to the main API

Phase 2 OpenAI and Anthropic parity must satisfy the agent-grade provider requirements in:

- `docs/provider-capability-streaming-reference.md`
- `docs/streaming-provider-gaps-spec.md`

Those same documents remain Phase 3 guidance for additional providers such as Gemini, Ollama, MLX, CoreML, Llama, and SystemLanguageModel, but OpenAI and Anthropic cannot be marked Phase 2 complete without the relevant capability, rich streaming event, transcript-first reduction, metadata, warning/error, replay, and test coverage described there.

## Rule

Build whole durable features across their natural boundaries.

Do not introduce interim protocols, placeholder types, bridge sessions, adapter shims, or compatibility-only typealiases just to keep work inside an artificial phase boundary. If an ALM type naturally depends on `LanguageModel`, `LanguageModelSession`, `Transcript`, `GenerationOptions`, provider requests, or streaming events, move or design the connected pieces together.

## Reverification Summary

Reverified on April 25, 2026:

- The previous completed primitive items are valid carry-forward work.
- Those items should not be counted as completing the broader Phase 2 model-stack workstreams.
- No completed item below was found to be false; statuses now distinguish implemented primitive work from partial migration/test coverage.
- `JSONValue`, `GenerationOptions`, `LanguageModel`, and `LanguageModelSession` now have a main SwiftAgent implementation.
- Direct OpenAI, Open Responses, and Anthropic providers now run through `SwiftAgent.HTTPClient`, `LanguageModelSession`, transcript-first streaming, session-owned tool execution policy, token usage, image prompt segments, structured string conveniences, and provider response metadata.
- AgentRecorder scenarios and `Sources/ExampleCode/ReadmeCode.swift` now use `import SwiftAgent` and `LanguageModelSession(model:tools:instructions:)`.
- `SimulationLanguageModel` now runs through `LanguageModelSession`; the old `LanguageModelProvider`/`Adapter` stack was removed.
- MacPaw `OpenAI` and `SwiftAnthropic` removal was explicitly approved and implemented.
- README migration was handled as a preserve-first edit so existing sections such as Groundings and Logging remain.

Evidence checked:

- `grep -RIn "FoundationModels" Sources Tests AgentRecorder Examples Package.swift` returned no results.
- `Sources/SwiftAgent/Core/` contains the ALM-derived primitive files listed below.
- SwiftAgent now exposes initial main `JSONValue`, `GenerationOptions`, `LanguageModel`, and `LanguageModelSession(model:tools:instructions:)` implementations.
- Current source no longer contains `LanguageModelProvider`, `AdapterUpdate`, `AdapterGenerationOptions`, `OpenAIGenerationOptions`, or `AnthropicGenerationOptions`.
- `Package.swift` exposes a `SwiftAgent` library product. The old OpenAI/Anthropic provider-session products and targets were removed. The `SimulatedSession` product remains as the simulation helper product, now centered on `SimulationLanguageModel`.

## Core Primitive And Macro Work

The earlier main-type work remains valid and is recorded in `docs/phase-2-canonical-types-results.md`. These items are complete only for their stated primitive/macro/test scope.

| Item | Status | Evidence / Notes |
| --- | --- | --- |
| SwiftAgent core no longer imports Apple `FoundationModels` for local core primitive constraints. | Implemented | Reverified with `grep`; no `FoundationModels` references remain in `Sources`, `Tests`, `AgentRecorder`, `Examples`, or `Package.swift`. |
| SwiftAgent owns local `GeneratedContent`. | Implemented | Implemented in `Sources/SwiftAgent/Core/GeneratedContent.swift`; stable JSON behavior is preserved for transcript/replay use. |
| SwiftAgent owns local `Generable`. | Implemented | Implemented in `Sources/SwiftAgent/Core/Generable.swift`. |
| SwiftAgent owns local `GenerationSchema`. | Implemented | Implemented in `Sources/SwiftAgent/Core/GenerationSchema.swift`; direct OpenAI/Open Responses and Anthropic providers use the local schema path. |
| SwiftAgent owns local `DynamicGenerationSchema`. | Implemented | Implemented in `Sources/SwiftAgent/Core/DynamicGenerationSchema.swift`. |
| SwiftAgent owns local `GenerationGuide`. | Implemented | Implemented in `Sources/SwiftAgent/Core/GenerationGuide.swift`; local `@Guide` wiring exists. |
| SwiftAgent owns local `GenerationID`. | Implemented | Implemented in `Sources/SwiftAgent/Core/GenerationID.swift`. |
| SwiftAgent owns local `Tool`. | Implemented | Implemented in `Sources/SwiftAgent/Core/Tool.swift`; main session-owned tool execution policy is tracked separately below and is implemented for direct providers. |
| SwiftAgent owns local `Instructions`. | Implemented | Implemented in `Sources/SwiftAgent/Core/Instructions.swift`; `LanguageModelSession` records instructions in the transcript. |
| SwiftAgent owns local `Prompt` behavior. | Implemented | SwiftAgent prompt/source rendering remains main with ALM-compatible prompt tests migrated; direct providers consume `Prompt` through the main session. |
| SwiftAgent owns local `Availability`. | Implemented | Implemented in `Sources/SwiftAgent/Core/Availability.swift` with focused tests. |
| Required conversion protocols are local. | Implemented | Implemented in `Sources/SwiftAgent/Core/ConvertibleFromGeneratedContent.swift` and `Sources/SwiftAgent/Core/ConvertibleToGeneratedContent.swift`. |
| `@Generable` and `@Guide` macro wiring exists in SwiftAgent. | Implemented | ALM macro implementations were folded into `SwiftAgentMacros`; defaulted-property parity was fixed. |
| `@SessionSchema` emits local core types. | Implemented | Macro expansions use `SwiftAgent.Tool`, local `StructuredOutput`, and local grounding types; README and `Sources/ExampleCode/ReadmeCode.swift` keep `@SessionSchema` examples. |
| Initial ALM core tests migrated. | Implemented for Phase 2 | Focused tests for conversion, dynamic schema, guide, prompt, instructions, availability, and macro parity exist. Current-provider ALM parity was audited and covered with provider-specific replay tests for OpenAI, Open Responses, and Anthropic. Later optional-provider ALM tests move with their provider phases. |

## Remaining Phase 2 Workstreams

| Workstream | Status | Completion Meaning |
| --- | --- | --- |
| Main `GenerationOptions` / `JSONValue` / custom options | Implemented | Added dependency-backed `JSONValue` and main `GenerationOptions` with typed model custom options through the real `LanguageModel` relationship. Direct OpenAI/Open Responses, Anthropic, and Simulation request/generation paths consume the main options/custom-options path. Legacy provider-session option types were removed. |
| Main `LanguageModel` | Implemented | Added main `LanguageModel` provider boundary used by `LanguageModelSession`; direct OpenAI, Open Responses, Anthropic, and Simulation providers conform and have focused tests. |
| Main `LanguageModelSession` | Implemented | Added `LanguageModelSession(model:tools:instructions:)` with SwiftAgent transcript and token usage state, transcript-derived stream snapshots, per-turn response IDs, image prompt entries, schema-aware grounding conveniences, structured string conveniences, session-owned tool execution policy, and response/snapshot metadata. Legacy provider-session architecture was removed. |
| Merged transcript | Implemented for Phase 2 | Added instructions entries with tool definitions, image segments, provider-facing prompt/tool-output conveniences, per-turn response IDs, typed grounding source storage, reasoning/tool/response entries, and stable coding behavior. Later structured-output source classification and schema-version/diff helpers remain follow-up infrastructure, not blockers for the Phase 2 no-bridge merge. |
| Transcript-first streaming | Implemented for direct providers | Direct OpenAI/Open Responses and Anthropic streams emit transcript entries for text, streamed tool calls/tool outputs, Anthropic thinking/signature, token usage, and response metadata through main session snapshots. |
| Tool execution policy | Implemented | Session owns generated tool-call handling, delegate approval/stop/provided-output hooks, serial/parallel execution, retry policy, missing-tool behavior, and failure behavior with focused tests. Streaming provider loops execute tools through this policy. |
| OpenAI direct provider parity | Implemented | `OpenAILanguageModel` and `OpenResponsesLanguageModel` use `SwiftAgent.HTTPClient`, main session tool policy, PartialJSONDecoder-backed structured streaming, images, capabilities, response metadata, AgentRecorder scenarios, and provider-specific replay tests for text/tool/streaming/token-usage/request-shape paths. MacPaw `OpenAI` was removed after approval. |
| Anthropic direct provider parity | Implemented | `AnthropicLanguageModel` uses `SwiftAgent.HTTPClient`, main session tool policy, PartialJSONDecoder-backed structured streaming, images, capabilities, thinking/signature streaming, response metadata, AgentRecorder scenarios, and provider-specific replay tests for text/tool/streaming/token-usage/request-shape paths. `SwiftAnthropic` was removed after approval. |
| Provider transport / replay / logging | Implemented for Phase 2 | Direct providers use `SwiftAgent.HTTPClient` as the provider transport; `URLSessionHTTPClient` is the default; AsyncHTTPClient support is a SwiftPM trait on `SwiftAgent`, not a base dependency. Copied ALM `HTTPSession`/URLSession helper transport is not left as the final provider path. Existing SwiftAgent replay/logging paths remain the active infrastructure. |
| Public package/API surface | Implemented | `import SwiftAgent` exposes the main core API through a `SwiftAgent` library product. Old `OpenAISession`, `AnthropicSession`, `LanguageModelProvider`, and `Adapter` products/types were removed. |
| AgentRecorder/examples/docs | Implemented | AgentRecorder scenarios, Example App, `Sources/ExampleCode/ReadmeCode.swift`, and README use the main merged API while preserving existing README sections. Simulation examples use `SimulationLanguageModel`. |
| ALM current-provider tests | Implemented | Current-provider ALM coverage was audited and split into `OpenAIProviderReplayTests`, `OpenResponsesProviderReplayTests`, and `AnthropicProviderReplayTests`, backed by SwiftAgent `ReplayHTTPClient` rather than live network tests. |
| Dependency removal proposals | Implemented for approved dependencies | The user explicitly approved removing MacPaw `OpenAI` and `SwiftAnthropic`; both dependencies, old provider-session targets, and old provider-session tests were removed. |

## Approved Dependency Additions

The user approved adding these dependencies during the merged Phase 2 when the implementation needs them:

- `JSONSchema`
- `PartialJSONDecoder`

Do not rewrite ALM JSON/schema or partial structured decoding code just to avoid these dependencies.

## Still Requires Explicit Approval

- Removing dependencies from `External/AnyLanguageModel`.
- Adding MLX, Llama, CoreML, or AsyncHTTPClient to the base SwiftAgent target.
- Pruning or deleting `External/AnyLanguageModel`.

## Phase 2 Transport Decision

- Mechanical copy from `External/AnyLanguageModel` is a reviewability tactic, not the final architecture.
- Copied provider code must be absorbed into SwiftAgent's main session, transcript, tool policy, replay, and logging stack.
- Direct providers should use `SwiftAgent.HTTPClient` as their provider transport.
- `URLSessionHTTPClient` remains the default transport implementation.
- AsyncHTTPClient support is added as an optional SwiftPM trait on the `SwiftAgent` target for server-oriented users.
- AsyncHTTPClient must not be added to the base `SwiftAgent` target unless separately approved for that target.
- ALM `HTTPSession`, copied `Transport.swift`, and copied URLSession-only provider helpers must not be left as the final direct-provider transport.

## Completion Rule

Phase 2 is complete only when every remaining workstream above is either:

- implemented with validation evidence, or
- explicitly deferred with a reason and a new owner phase that does not require temporary architecture in the meantime.

An item must not be marked complete if it was satisfied by an interim protocol, placeholder type, bridge session, adapter shim, or compatibility-only typealias that exists only to avoid connected architecture.
