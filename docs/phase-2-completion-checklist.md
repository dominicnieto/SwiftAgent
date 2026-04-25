# Phase 2 Completion Checklist

## Phase Definition

Phase 2 is complete when SwiftAgent has a coherent local FoundationModels-style core replacement layer.

Phase 2 does not include transcript/session streaming redesign, direct OpenAI/Anthropic provider replacement, provider SDK removal, dependency removal, or optional local-provider product work.

Small implementation slices are allowed, but they are only a way to complete this checklist. They do not redefine Phase 2.

## Current Status

Status: partial / first vertical slice plus defaulted-property parity and initial ALM core test migration slices complete.

The first Phase 2 implementation slice completed the local primitive stack and macro/reference updates recorded in `docs/phase-2-canonical-types-results.md`. The next slice resolved `@Generable` defaulted-property parity. The latest slice migrated focused ALM core tests for `ConvertibleToGeneratedContent`, `DynamicGenerationSchema`, and `GenerationGuide` into `SwiftAgentTests`. Phase 2 remains incomplete because the broader merge docs still require additional canonical core work, especially `Prompt`, `GenerationOptions`, `LanguageModel`, `Availability`, broader ALM core test migration/classification, and dependency decisions for any moved ALM JSON/schema/partial-decoding code.

## Reconciliation Sources

This checklist was reconciled against:

- `docs/any-language-model-merge-plan.md`
- `docs/any-language-model-merge-spec.md`
- `docs/any-language-model-merge-decisions.md`
- `docs/dependency-migration-plan.md`
- `docs/merge-test-matrix.md`
- `docs/package-layout-spec.md`
- `docs/phase-0-inventory.md`
- `docs/phase-1-copy-results.md`
- `docs/phase-2-canonical-types-results.md`
- `docs/agent-recorder-merge-plan.md`
- `docs/provider-capability-streaming-reference.md`
- `docs/streaming-provider-gaps-spec.md`
- `plans/README.md`
- `plans/phase-0-inventory-plan.md`
- `plans/phase-1-copy-any-language-model-plan.md`
- `plans/phase-2-canonical-types-plan.md`

## Completion Criteria

| Item | Status | Evidence / Notes |
| --- | --- | --- |
| SwiftAgent core no longer imports Apple `FoundationModels` for `Generable`, `GeneratedContent`, `GenerationSchema`, `Tool`, and related core constraints. | Done | Verified with `grep -RInE "import FoundationModels|FoundationModels\\." Sources Tests AgentRecorder Examples Package.swift`; no results. Apple FoundationModels compatibility remains only in copied ALM/SystemLanguageModel material for later phases. |
| SwiftAgent owns local `GeneratedContent`. | Done | Implemented in `Sources/SwiftAgent/Core/GeneratedContent.swift`; compiled by `SwiftAgentTests` build and full test plan. Stable JSON behavior verified by `TranscriptCodableTests`. |
| SwiftAgent owns local `Generable`. | Done | Implemented in `Sources/SwiftAgent/Core/Generable.swift`; consumed by SwiftAgent source, providers, examples, AgentRecorder scenarios, and tests. |
| SwiftAgent owns local `GenerationSchema`. | Done | Implemented in `Sources/SwiftAgent/Core/GenerationSchema.swift`; current provider SDK schema conversion remained compatible under full `SwiftAgentTests`. |
| SwiftAgent owns local `DynamicGenerationSchema`. | Done for first slice | Implemented in `Sources/SwiftAgent/Core/DynamicGenerationSchema.swift`. Dedicated ALM dynamic schema tests still need migration/classification before Phase 2 can be complete. |
| SwiftAgent owns local `GenerationGuide`. | Done for first slice | Implemented in `Sources/SwiftAgent/Core/GenerationGuide.swift` and consumed by local `@Guide`. Dedicated ALM guide tests still need migration/classification before Phase 2 can be complete. |
| SwiftAgent owns local `GenerationID`. | Done | Implemented in `Sources/SwiftAgent/Core/GenerationID.swift`. |
| SwiftAgent owns local `Tool`. | Done | Implemented in `Sources/SwiftAgent/Core/Tool.swift`; provider/test/example/AgentRecorder tool conformances now use `SwiftAgent.Tool`. |
| SwiftAgent owns local `Instructions`. | Done for first slice | Implemented in `Sources/SwiftAgent/Core/Instructions.swift`. Full transcript/session integration for instruction entries remains Phase 3/session work. |
| Required conversion protocols are local. | Done | Implemented in `Sources/SwiftAgent/Core/ConvertibleFromGeneratedContent.swift` and `Sources/SwiftAgent/Core/ConvertibleToGeneratedContent.swift`. |
| `@Generable` and `@Guide` macro wiring exists in SwiftAgent. | Done for first slice | Added `Sources/SwiftAgentMacros/GenerableMacro.swift`, `Sources/SwiftAgentMacros/GuideMacro.swift`, and `SwiftAgentMacroPlugin` registration. Macro test plan passed. Defaulted-property parity is tracked separately below and is now done. |
| `@SessionSchema` emits local core types. | Done | `SessionSchemaMacro` emits `SwiftAgent.Tool`; macro expansion expectations updated and macro test plan passed. |
| Existing transcript codable/stable JSON behavior still works. | Done | Focused `TranscriptCodableTests` passed; full `SwiftAgentTests` passed. |
| Existing prompt/source rendering behavior still works. | Done | Full `SwiftAgentTests` passed, including existing `PromptBuilderTests`. No transcript/source metadata redesign was attempted in this slice. |
| Existing decodable tool schema behavior still works. | Done | Focused `DecodableToolJSONSchemaTests` passed; full `SwiftAgentTests` passed. |
| Existing provider schema conversion through current SDK adapters still works. | Done | Full OpenAI/Anthropic/Simulated SwiftAgent test suite passed while MacPaw `OpenAI` and `SwiftAnthropic` remain in place. |
| Example and AgentRecorder compile after local primitive adoption. | Done with environment note | ExampleApp iPhone 17 Pro simulator build passed. AgentRecorder compiled with `CODE_SIGNING_ALLOWED=NO`; plain AgentRecorder build is blocked locally by a missing Mac Development signing certificate. |
| `External/AnyLanguageModel` remains intact. | Done | No uncommitted diffs under `External/AnyLanguageModel`; stray generated `External/.DS_Store` was removed. |
| Root package dependencies remain unchanged. | Done | No uncommitted diffs in `Package.swift` or `Package.resolved`; no dependency additions/removals. |
| Provider SDK replacement did not start. | Done | MacPaw `OpenAI` and `SwiftAnthropic` usage remains; no direct-provider migration or adapter deletion occurred. |
| Phase 3 transcript/session streaming redesign did not start. | Done | No canonical transcript/session streaming reducer, provider capability model, or direct provider event stream was implemented in this slice. |
| Relevant ALM core tests are moved/adapted or explicitly deferred with reasons. | Incomplete | Initial focused core migration added SwiftAgent-native tests adapted from ALM for `ConvertibleToGeneratedContent`, `DynamicGenerationSchema`, and `GenerationGuide` under `Tests/SwiftAgentTests/Core/`; focused tests passed. Broader ALM core tests for generated content, schemas, prompt, instructions, transcript, generation options, and tool execution still need migration/classification. |
| `Prompt` canonical ownership is implemented or explicitly tracked as remaining Phase 2 work. | Incomplete | Merge spec lists `Prompt` as a canonical model primitive. This slice kept SwiftAgent's current prompt stack and only removed availability friction needed by ALM conversion protocols. |
| `LanguageModel` canonical ownership is implemented or explicitly tracked as remaining Phase 2 work. | Incomplete | Merge spec lists `LanguageModel` as a canonical primitive/provider boundary. This slice did not move ALM `LanguageModel` into SwiftAgent. |
| `Availability` canonical ownership is implemented or explicitly tracked as remaining Phase 2 work. | Incomplete | Merge spec lists `Availability` as a canonical model primitive. This slice did not move ALM `Availability` into SwiftAgent. |
| `GenerationOptions` canonical decision is implemented or explicitly marked as remaining Phase 2 work. | Incomplete | Decisions/spec require unified `GenerationOptions`; this slice preserved provider-specific generation options and records the unified options work as a follow-up. |
| `JSONValue` / `JSONSchema` dependency decision is resolved for Phase 2. | Incomplete | No `JSONValue`, direct provider request builders, or provider-neutral schema conversion moved into SwiftAgent yet. If they do, docs require proposing `JSONSchema` rather than rewriting around it, with explicit approval before `Package.swift` changes. |
| `PartialJSONDecoder` decision is resolved for Phase 2. | Incomplete | No structured streaming engine or ALM partial snapshot path moved in this slice. Docs allow deferring this to the structured streaming/session work if Phase 2 does not need it. |
| `@Generable` defaulted-property parity is resolved or explicitly deferred with approval. | Done | `Sources/SwiftAgentMacros/GenerableMacro.swift` now preserves stored-property default expressions in generated memberwise initializers and uses them for missing generated-content fields. Verified by `Tests/SwiftAgentTests/Protocols/GenerableMacroDefaultedPropertyTests.swift`, focused SwiftAgent test, macro test plan, full SwiftAgent test plan, and required builds. |
| `docs/phase-2-canonical-types-results.md` records implementation status, commands, validation, dependency decisions, and deferred work. | Done | Results doc says `Phase 2 status: partial`, records validation, cleanup, dependency decisions, and follow-ups. |

## Remaining Phase 2 Work

- Commit the current initial ALM core test migration slice if accepted.
- Continue moving/adapting relevant ALM core tests or explicitly defer them with reasons.
- Decide whether current first-slice and initial migrated coverage is sufficient or add more dedicated SwiftAgent tests for local `GeneratedContent`, `GenerationSchema`, `DynamicGenerationSchema`, `GenerationGuide`, and `@Generable` parity.
- Resolve canonical `Prompt`, `LanguageModel`, and `Availability` ownership for SwiftAgent or explicitly amend Phase 2 scope.
- Resolve the `GenerationOptions` / `JSONValue` slice.
- Request approval for `JSONSchema` if the `GenerationOptions` / `JSONValue` slice naturally needs it.
- Decide whether `PartialJSONDecoder` is needed in Phase 2 or explicitly deferred to Phase 3.
- Update this checklist as items move to done.

## Dependency Guidance

Do not rewrite AnyLanguageModel JSON/schema/provider code merely to avoid dependencies.

`JSONSchema` is likely the correct provider-neutral dependency once AnyLanguageModel `GenerationOptions`, `JSONValue`, direct provider request builders, or provider-neutral schema conversion move into SwiftAgent.

`PartialJSONDecoder` is likely the correct dependency when structured streaming or partial snapshots move into the merged session engine.

Both still require explicit approval before editing `Package.swift`.

## Out Of Scope For Phase 2

- Transcript/session streaming redesign.
- Direct OpenAI provider replacement.
- Direct Anthropic provider replacement.
- Provider SDK removal.
- Dependency removal.
- Optional MLX/CoreML/Llama provider product work.
- AgentRecorder migration to direct providers, except for compile fixes required by the local primitive slice.

## Completion Rule

Phase 2 is complete only when every completion criterion above is either:

- `Done`, with evidence, or
- `Deferred with approval`, with a reason and a later-phase owner.

If any criterion is still `In progress`, `Incomplete`, `Not verified`, or `Needs verification`, Phase 2 remains partial.
