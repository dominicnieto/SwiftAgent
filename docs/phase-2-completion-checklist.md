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

## Rule

Build whole durable features across their natural boundaries.

Do not introduce interim protocols, placeholder types, bridge sessions, adapter shims, or compatibility-only typealiases just to keep work inside an artificial phase boundary. If an ALM type naturally depends on `LanguageModel`, `LanguageModelSession`, `Transcript`, `GenerationOptions`, provider requests, or streaming events, move or design the connected pieces together.

## Reverification Summary

Reverified on April 25, 2026:

- The previous completed primitive items are valid carry-forward work.
- Those items should not be counted as completing the broader Phase 2 model-stack workstreams.
- No completed item below was found to be false, but several old `Done` labels were narrowed to `Verified carry-forward` so they do not imply full session/provider/streaming completion.
- `GenerationOptions`, `JSONValue`, `LanguageModel`, `LanguageModelSession`, transcript-first streaming, tool execution policy, OpenAI direct provider parity, Anthropic direct provider parity, and AgentRecorder/example migration remain not complete.

Evidence checked:

- `grep -RIn "FoundationModels" Sources Tests AgentRecorder Examples Package.swift` returned no results.
- `Sources/SwiftAgent/Core/` contains the ALM-derived primitive files listed below.
- No canonical SwiftAgent `GenerationOptions`, `JSONValue`, `LanguageModel`, or `LanguageModelSession(model:tools:instructions:)` implementation exists yet.
- Current provider paths still reference `AdapterGenerationOptions`, `OpenAIGenerationOptions`, `AnthropicGenerationOptions`, and `SimulationGenerationOptions`.
- `Package.swift` does not yet expose a `SwiftAgent` library product; public products are still provider-session shaped.
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
| Canonical `GenerationOptions` / `JSONValue` / custom options | Not complete | Move ALM `GenerationOptions` with its real `LanguageModel` relationship. Add `JSONSchema` when moving `JSONValue` or provider request/custom option code. Do not introduce a smaller custom-options-only provider protocol. |
| Canonical `LanguageModel` | Not complete | Move/design `LanguageModel` as the actual provider boundary used by direct providers and session APIs. |
| Canonical `LanguageModelSession` | Not complete | Implement the real `LanguageModelSession(model:tools:instructions:)` engine with SwiftAgent transcript, token usage, replay/logging, schema, and tool policy behavior. |
| Merged transcript | Not complete | Merge ALM additions into SwiftAgent's agent-grade transcript without losing reasoning, call IDs, statuses, source metadata, stable coding, or resolver behavior. |
| Transcript-first streaming | Not complete | Providers emit rich events; session reduces them into transcript/token state; snapshots derive from that state. |
| Tool execution policy | Not complete | Session owns tool execution, parallelism, retries, missing-tool behavior, failure behavior, and approval hooks. |
| OpenAI direct provider parity | Not complete | `OpenAILanguageModel` and `OpenResponsesLanguageModel` pass text, structured output, tool, streaming, reasoning, token usage, metadata, and replay tests through the canonical session. |
| Anthropic direct provider parity | Not complete | `AnthropicLanguageModel` passes text, structured output, tool, streaming thinking/reasoning, token usage, metadata, and replay tests through the canonical session. |
| Public package/API surface | Not complete | `import SwiftAgent` exposes the canonical core API through a `SwiftAgent` library product. Provider-session products are removed or retained only as thin conveniences after parity decisions. |
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

## Completion Rule

Phase 2 is complete only when every remaining workstream above is either:

- implemented with validation evidence, or
- explicitly deferred with a reason and a new owner phase that does not require temporary architecture in the meantime.

An item must not be marked complete if it was satisfied by an interim protocol, placeholder type, bridge session, adapter shim, or compatibility-only typealias that exists only to avoid connected architecture.
