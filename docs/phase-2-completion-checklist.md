# Phase 2 Core Model Stack Merge Checklist

## Status

Status: in progress / partially completed canonical core work.

This checklist supersedes the earlier narrow Phase 2 checklist. The old plan separated canonical types, transcript/streaming, OpenAI provider replacement, and Anthropic provider replacement into separate phases. That split is no longer the working model because it encourages temporary protocols and compatibility scaffolding.

Phase 2 now means the full core model stack merge:

- canonical core primitives and options
- `LanguageModel`
- `LanguageModelSession`
- transcript-first streaming
- tool execution policy
- direct OpenAI provider parity
- direct Anthropic provider parity
- AgentRecorder/examples/docs migration to the canonical API

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
- No completed item below was found to be false, but several old `Done` labels were narrowed to `Verified carry-forward` so they do not imply full session/provider/streaming completion.
- `JSONValue`, `GenerationOptions`, `LanguageModel`, and `LanguageModelSession` now have an initial canonical SwiftAgent implementation, but the broader connected workstream remains partial until direct providers, full transcript merging, tool execution policy, and AgentRecorder/examples/docs are migrated.
- Transcript-first streaming, tool execution policy, OpenAI direct provider parity, Anthropic direct provider parity, and AgentRecorder/example migration remain not complete.

Evidence checked:

- `grep -RIn "FoundationModels" Sources Tests AgentRecorder Examples Package.swift` returned no results.
- `Sources/SwiftAgent/Core/` contains the ALM-derived primitive files listed below.
- SwiftAgent now exposes initial canonical `JSONValue`, `GenerationOptions`, `LanguageModel`, and `LanguageModelSession(model:tools:instructions:)` implementations.
- Current provider paths still reference `AdapterGenerationOptions`, `OpenAIGenerationOptions`, `AnthropicGenerationOptions`, and `SimulationGenerationOptions`.
- `Package.swift` now exposes a `SwiftAgent` library product, while the old provider-session products still remain.
- `README.md` still documents old `OpenAISession` / `AnthropicSession` usage and includes Apple `FoundationModels` imports.

## Verified Carry-Forward Work

The earlier canonical-type work remains valid and is recorded in `docs/phase-2-canonical-types-results.md`. These items are complete only for their stated primitive/macro/test scope.

| Item | Status | Evidence / Notes |
| --- | --- | --- |
| SwiftAgent core no longer imports Apple `FoundationModels` for local core primitive constraints. | Verified carry-forward | Reverified with `grep`; no `FoundationModels` references remain in `Sources`, `Tests`, `AgentRecorder`, `Examples`, or `Package.swift`. |
| SwiftAgent owns local `GeneratedContent`. | Verified carry-forward | Implemented in `Sources/SwiftAgent/Core/GeneratedContent.swift`; existing stable JSON behavior is carry-forward evidence, but broader transcript/session integration remains part of merged Phase 2. |
| SwiftAgent owns local `Generable`. | Verified carry-forward | Implemented in `Sources/SwiftAgent/Core/Generable.swift`. |
| SwiftAgent owns local `GenerationSchema`. | Verified carry-forward | Implemented in `Sources/SwiftAgent/Core/GenerationSchema.swift`; current provider SDK schema conversion remains old-adapter behavior until direct providers migrate. |
| SwiftAgent owns local `DynamicGenerationSchema`. | Verified carry-forward | Implemented in `Sources/SwiftAgent/Core/DynamicGenerationSchema.swift`; broader ALM test migration can move with full stack work. |
| SwiftAgent owns local `GenerationGuide`. | Verified carry-forward | Implemented in `Sources/SwiftAgent/Core/GenerationGuide.swift`; local `@Guide` wiring exists. |
| SwiftAgent owns local `GenerationID`. | Verified carry-forward | Implemented in `Sources/SwiftAgent/Core/GenerationID.swift`. |
| SwiftAgent owns local `Tool`. | Verified carry-forward | Implemented in `Sources/SwiftAgent/Core/Tool.swift`; this does not complete session-owned tool execution policy. |
| SwiftAgent owns local `Instructions`. | Verified carry-forward | Implemented in `Sources/SwiftAgent/Core/Instructions.swift`; transcript/session instruction integration remains part of merged Phase 2. |
| SwiftAgent owns local `Prompt` behavior. | Verified carry-forward | SwiftAgent prompt/source rendering remains canonical with ALM-compatible prompt tests migrated; prompt response-format/options integration remains part of merged transcript/session work. |
| SwiftAgent owns local `Availability`. | Verified carry-forward | Implemented in `Sources/SwiftAgent/Core/Availability.swift` with focused tests. |
| Required conversion protocols are local. | Verified carry-forward | Implemented in `Sources/SwiftAgent/Core/ConvertibleFromGeneratedContent.swift` and `Sources/SwiftAgent/Core/ConvertibleToGeneratedContent.swift`. |
| `@Generable` and `@Guide` macro wiring exists in SwiftAgent. | Verified carry-forward | ALM macro implementations were folded into `SwiftAgentMacros`; defaulted-property parity was fixed. |
| `@SessionSchema` emits local core types. | Verified carry-forward | Macro expansions use `SwiftAgent.Tool`; generated code still needs to align with the final merged transcript/session API when that API lands. |
| Initial ALM core tests migrated. | Partial carry-forward | Focused tests for conversion, dynamic schema, guide, prompt, instructions, availability, and macro parity exist. More tests move with the relevant full feature workstreams. |

## Remaining Phase 2 Workstreams

| Workstream | Status | Completion Meaning |
| --- | --- | --- |
| Canonical `GenerationOptions` / `JSONValue` / custom options | Partial | Added dependency-backed `JSONValue` and canonical `GenerationOptions` with typed model custom options through the real `LanguageModel` relationship. Provider-specific custom option types and direct provider request usage still need migration. |
| Canonical `LanguageModel` | Partial | Added canonical `LanguageModel` provider boundary used by `LanguageModelSession`; direct OpenAI, Open Responses, and Anthropic providers now conform. More provider metadata/capability validation still needs hardening before this workstream is complete. |
| Canonical `LanguageModelSession` | Partial | Added `LanguageModelSession(model:tools:instructions:)` with SwiftAgent transcript and token usage state, transcript-derived stream snapshots, and session-owned tool execution policy. Response/snapshot metadata, warnings, logging integration, and old-session convergence remain. |
| Merged transcript | Partial | Added instructions entries with tool definitions, image segments, and provider-facing prompt/tool-output conveniences while preserving existing prompt/reasoning/tool/response entries and stable coding behavior. Prompt response format/options, structured-output source tracking, schema versioning, and focused diff helpers remain. |
| Transcript-first streaming | Partial | Direct OpenAI/Open Responses and Anthropic streams now emit transcript entries for text, streamed tool calls/tool outputs, Anthropic thinking/signature, and token usage through canonical session snapshots. Full normalized metadata/warning/error events and complete provider event coverage remain. |
| Tool execution policy | Partial | Session owns generated tool-call handling, delegate approval/stop/provided-output hooks, serial/parallel execution, retry policy, missing-tool behavior, and failure behavior with focused tests. Streaming provider loops now execute tools through this policy. Broader approval UX/logging integration remains. |
| OpenAI direct provider parity | Partial | `OpenAILanguageModel` and `OpenResponsesLanguageModel` use `SwiftAgent.HTTPClient`, canonical session tool policy, PartialJSONDecoder-backed structured streaming, images, capabilities, and replay tests for text/tool/streaming/token-usage paths. Full metadata/warnings/errors, complete reasoning event coverage, AgentRecorder migration, and old SDK dependency removal approval remain. |
| Anthropic direct provider parity | Partial | `AnthropicLanguageModel` uses `SwiftAgent.HTTPClient`, canonical session tool policy, PartialJSONDecoder-backed structured streaming, images, capabilities, and replay tests for text/tool/streaming thinking/signature/token-usage paths. Full metadata/warnings/errors, beta fine-grained coverage, AgentRecorder migration, and old SDK dependency removal approval remain. |
| Provider transport / replay / logging | Partial | Direct providers use `SwiftAgent.HTTPClient` as the provider transport; `URLSessionHTTPClient` is the default; AsyncHTTPClient support was added as an optional SwiftAgent `HTTPClient` adapter target/product. Copied ALM `HTTPSession`/URLSession helper transport is not left as the final provider path. Network logging/replay metadata surfacing still needs completion. |
| Public package/API surface | Partial | `import SwiftAgent` now exposes the canonical core API through a `SwiftAgent` library product. Provider-session products still remain and are not yet thin conveniences over the canonical session. |
| AgentRecorder/examples/docs | Not complete | Public examples, `README.md`, and recorder scenarios use the canonical merged API after provider parity exists. |
| Dependency removal proposals | Not complete | MacPaw `OpenAI` and `SwiftAnthropic` removal require explicit approval after parity evidence. |

## Approved Dependency Additions

The user approved adding these dependencies during the merged Phase 2 when the implementation needs them:

- `JSONSchema`
- `PartialJSONDecoder`

Do not rewrite ALM JSON/schema or partial structured decoding code just to avoid these dependencies.

## Still Requires Explicit Approval

- Removing MacPaw `OpenAI`.
- Removing `SwiftAnthropic`.
- Removing dependencies from `External/AnyLanguageModel`.
- Adding MLX, Llama, CoreML, or AsyncHTTPClient to the base SwiftAgent target.
- Pruning or deleting `External/AnyLanguageModel`.

## Phase 2 Transport Decision

- Mechanical copy from `External/AnyLanguageModel` is a reviewability tactic, not the final architecture.
- Copied provider code must be absorbed into SwiftAgent's canonical session, transcript, tool policy, replay, and logging stack.
- Direct providers should use `SwiftAgent.HTTPClient` as their provider transport.
- `URLSessionHTTPClient` remains the default transport implementation.
- AsyncHTTPClient support should be added as an optional SwiftAgent `HTTPClient` adapter target/product for server-oriented users.
- AsyncHTTPClient must not be added to the base `SwiftAgent` target unless separately approved for that target.
- ALM `HTTPSession`, copied `Transport.swift`, and copied URLSession-only provider helpers must not be left as the final direct-provider transport.

## Completion Rule

Phase 2 is complete only when every remaining workstream above is either:

- implemented with validation evidence, or
- explicitly deferred with a reason and a new owner phase that does not require temporary architecture in the meantime.

An item must not be marked complete if it was satisfied by an interim protocol, placeholder type, bridge session, adapter shim, or compatibility-only typealias that exists only to avoid connected architecture.
