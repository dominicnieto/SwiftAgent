# Phase 2 Canonical Types Plan

## Phase Goal

Choose the canonical SwiftAgent core type ownership for the AnyLanguageModel merge before implementation begins. Phase 2 is a planning and approval phase only: it records which duplicate concepts should be absorbed from AnyLanguageModel, which SwiftAgent behaviors must remain authoritative, and which merged types need explicit design work.

The approved result should guide the later implementation that removes long-term duplicate model stacks without creating a bridge between SwiftAgent adapters and AnyLanguageModel sessions.

## Source Docs Read

- `docs/any-language-model-merge-plan.md`
- `docs/any-language-model-merge-spec.md`
- `docs/any-language-model-merge-decisions.md`
- `docs/dependency-migration-plan.md`
- `docs/package-layout-spec.md`
- `docs/phase-0-inventory.md`
- `docs/phase-1-copy-results.md`
- `docs/merge-test-matrix.md`
- `plans/README.md`
- `plans/phase-1-copy-any-language-model-plan.md`

Additional source layout checked for planning context only:

- `Sources/SwiftAgent/`
- `Sources/OpenAISession/`
- `Sources/AnthropicSession/`
- `Sources/SimulatedSession/`
- `Sources/SwiftAgentMacros/`
- `External/AnyLanguageModel/Sources/AnyLanguageModel/`
- `External/AnyLanguageModel/Sources/AnyLanguageModelMacros/`
- `Tests/SwiftAgentTests/`
- `Tests/SwiftAgentMacroTests/`
- `External/AnyLanguageModel/Tests/AnyLanguageModelTests/`

## Scope

- Inventory duplicate core concepts between SwiftAgent and copied AnyLanguageModel.
- Propose one canonical source for each concept that must converge.
- Preserve SwiftAgent's agent-grade transcript, transcript resolution, token usage, replay, logging, and streaming UX requirements.
- Preserve AnyLanguageModel's useful FoundationModels-style core primitives and direct provider boundary.
- Identify files and areas expected to change in the later implementation phase.
- Identify dependency impacts that may need approval in later phases.
- Define approval gates before implementation starts.

## Non-Goals

- Do not edit Swift source files in this phase.
- Do not edit `Package.swift`.
- Do not move, prune, rename, or rewrite copied AnyLanguageModel files.
- Do not remove dependencies from SwiftAgent or the copied AnyLanguageModel package.
- Do not wire SwiftAgent targets to copied AnyLanguageModel targets yet.
- Do not replace provider SDK paths yet.
- Do not convert replay fixtures yet.
- Do not decide optional provider product layout beyond notes already needed for canonical type selection.
- Do not implement Phase 3 transcript/streaming reducers or Phase 4/5 provider replacements.

## Files And Areas Expected To Change Later

Later implementation will likely touch these areas after approval:

- `Sources/SwiftAgent/`: local core primitives, transcript, token usage, response/snapshot models, prompt/instructions, tool protocols, schema protocols, provider/session API, transport integration hooks.
- `Sources/SwiftAgent/LanguageModelProvider/`: replacement or collapse of `LanguageModelProvider`, `Adapter`, and provider update APIs into the canonical `LanguageModelSession` engine.
- `Sources/SwiftAgent/Models/`: merged `Transcript`, `AgentResponse`/`AgentSnapshot` or canonical response/snapshot shapes, `TokenUsage`, structured-output snapshot behavior.
- `Sources/SwiftAgent/Protocols/`: migration from Apple `FoundationModels` protocols to local `Generable`, `GeneratedContent`, `GenerationSchema`, and `Tool`.
- `Sources/SwiftAgent/Prompting/`: reconciliation of SwiftAgent prompt source metadata with AnyLanguageModel `Prompt` and `Instructions`.
- `Sources/SwiftAgent/Networking/`: keep SwiftAgent `HTTPClient`, `HTTPReplayRecorder`, `NetworkLog`, and SSE helpers as the long-term transport/replay direction.
- `Sources/SwiftAgentMacros/`: update `@SessionSchema` expansions to reference local core types instead of Apple `FoundationModels`.
- `Sources/OpenAISession/`, `Sources/AnthropicSession/`, `Sources/SimulatedSession/`: later migration or deprecation of provider-specific session/adapters once canonical `LanguageModelSession` can preserve behavior.
- `AgentRecorder/AgentRecorder/`: later migration from provider-specific sessions and SDK imports to canonical session/direct provider APIs.
- `Examples/` and `Sources/ExampleCode/`: later import/API updates after the canonical public surface exists.
- `External/AnyLanguageModel/Sources/AnyLanguageModel/`: source material for core primitives and provider implementations. Files should remain unmoved during this planning phase.
- `External/AnyLanguageModel/Sources/AnyLanguageModelMacros/`: source material for `@Generable` and `@Guide` macros.
- `Tests/SwiftAgentTests/`, `Tests/SwiftAgentMacroTests/`, and `External/AnyLanguageModel/Tests/AnyLanguageModelTests/`: later adaptation of SwiftAgent behavior tests and ALM core tests into the merged API.
- `Package.swift`: later dependency/target edits only after explicit approval.

## Duplicate Concept Inventory

- Core generated content: SwiftAgent currently imports Apple `FoundationModels.GeneratedContent`; AnyLanguageModel defines local `GeneratedContent`, conversion protocols, stable IDs, JSON conversion, and partial JSON support.
- Schema and generability: SwiftAgent currently relies on Apple `Generable` and `GenerationSchema`; AnyLanguageModel defines local `Generable`, `GenerationSchema`, `DynamicGenerationSchema`, `GenerationGuide`, and related macros.
- Prompting: SwiftAgent has prompt builder/source metadata for transcript resolving; AnyLanguageModel has FoundationModels-style `Prompt`, `PromptBuilder`, `PromptRepresentable`, `Instructions`, and `InstructionsBuilder`.
- Tooling: SwiftAgent wraps Apple `FoundationModels.Tool` into `SwiftAgentTool` and `DecodableTool`; AnyLanguageModel defines local `Tool`, argument/output conversion, schema injection, and `ToolExecutionDelegate`.
- Session/provider boundary: SwiftAgent uses `LanguageModelProvider`, `Adapter`, `AdapterUpdate`, provider-specific sessions, and SDK adapters; AnyLanguageModel uses `LanguageModel` providers plus `LanguageModelSession(model:tools:instructions:)`.
- Generation options: SwiftAgent has provider-specific `OpenAIGenerationOptions`, `AnthropicGenerationOptions`, and simulation options; AnyLanguageModel has one `GenerationOptions` with common fields and model-specific custom options.
- Transcript: SwiftAgent has agent-grade prompt/reasoning/tool/response entries, status, call IDs, upsert, resolved transcript APIs, and stable JSON helpers; AnyLanguageModel adds instructions entries, image segments, prompt options, response formats, and tool definitions.
- Streaming: SwiftAgent streams transcript/token updates and derives snapshots; AnyLanguageModel streams content/raw-content snapshots and appends transcript after completion in several paths.
- Token usage: SwiftAgent has public `TokenUsage` and accumulation outside transcript; AnyLanguageModel does not provide equivalent agent-grade token usage as a canonical session/snapshot concern.
- Structured output: SwiftAgent has `StructuredOutput`, `DecodableStructuredOutput`, `@SessionSchema`, transcript resolving, and UX snapshots; AnyLanguageModel has `@Generable`, `@Guide`, `StructuredGeneration`, and partial structured decoding.
- Transport/replay/logging: SwiftAgent has replay-aware `HTTPClient`, `HTTPReplayRecorder`, `NetworkLog`, and `AgentLog`; AnyLanguageModel has URLSession/AsyncHTTPClient helpers and provider-local request helpers.
- Provider identities/capabilities: SwiftAgent has typed provider model enums per SDK adapter; AnyLanguageModel has direct providers and mostly string model IDs, but the target architecture needs explicit capability metadata.

## Proposed Canonical Sources

| Concept | Proposed canonical source | Rationale |
| --- | --- | --- |
| `Generable` | AnyLanguageModel | ALM already provides the local FoundationModels-style replacement required to remove Apple `FoundationModels` imports. SwiftAgent should consume this directly instead of keeping a wrapper. |
| `GeneratedContent` | AnyLanguageModel, with SwiftAgent stable encoding behavior preserved | ALM owns the local content model and conversion protocols. SwiftAgent's stable JSON behavior must be folded in because replay fixtures and transcript codable tests depend on deterministic output. |
| `GenerationSchema` | AnyLanguageModel, with SwiftAgent provider JSON-schema conversion behavior preserved | ALM supplies the local schema representation and conversion tests. SwiftAgent's OpenAI/Anthropic schema mapping expectations remain required until provider parity replaces SDK adapters. |
| `DynamicGenerationSchema` | AnyLanguageModel | ALM already has a local dynamic schema model and tests; SwiftAgent currently depends on Apple concepts rather than owning a richer local equivalent. |
| `GenerationGuide` | AnyLanguageModel | ALM's guide model pairs with `@Guide`, `Generable`, and schema generation, so it should move with that stack. |
| `Prompt` | Merged, AnyLanguageModel-biased public type with SwiftAgent source metadata retained | ALM should provide the FoundationModels-style prompt builder shape. SwiftAgent must keep input/source metadata needed for transcript resolving, grounding, and replay/debuggability. |
| `Instructions` | AnyLanguageModel, extended for SwiftAgent transcript requirements | ALM has the canonical local instructions builder and transcript instructions entry. SwiftAgent needs this added without losing tool definition visibility. |
| `Tool` | AnyLanguageModel, with SwiftAgent `DecodableTool` ergonomics folded in where useful | ALM's tool protocol is already local, schema-aware, and model-session oriented. SwiftAgent's decodable tool and rejection/reporting behavior should become helpers or conformances around the canonical tool model. |
| `ToolExecutionDelegate / tool execution policy` | Merged, session-owned, SwiftAgent-biased policy semantics plus ALM delegate hook | ALM has a delegate hook, but merge docs require policy controls for parallel execution, retries, missing tools, failures, and approval. Providers should emit calls; canonical session should execute policy. |
| `LanguageModel` | AnyLanguageModel | ALM's `LanguageModel` is the desired direct provider boundary and enables replacing SDK adapters without a permanent bridge. |
| `LanguageModelSession` | Merged: ALM construction/provider boundary plus SwiftAgent state, transcript, streaming, token usage, schema, replay, and tool policy | The public API should prefer `LanguageModelSession(model:tools:instructions:)`, but ALM's current session is not agent-grade enough. SwiftAgent's transcript-first stream processing and token/state behavior must be built into the canonical session engine. |
| `GenerationOptions` | AnyLanguageModel, with SwiftAgent provider-specific options folded into custom options | The accepted decision is one common options type with model-specific custom options. This removes provider-specific session API pressure while preserving OpenAI/Anthropic power. |
| `Transcript` | Merged, SwiftAgent-biased with ALM additions | SwiftAgent's reasoning, call IDs, status, upsert, resolved transcript, and stable fixture behavior are mandatory. Add ALM instructions, image segments, prompt options/response format, and tool definitions. |
| streaming events / snapshots | Merged, SwiftAgent-biased transcript-first model | SwiftAgent's `AdapterUpdate.transcript` and `AdapterUpdate.tokenUsage` model matches the target direction. ALM content-only snapshots are insufficient; retain ALM `content`/`rawContent` convenience in public snapshots while adding transcript and token usage. |
| `TokenUsage` | SwiftAgent | SwiftAgent already models input/output/total/cached/reasoning usage and accumulates it outside transcript. This aligns with accepted decisions. |
| structured output protocols/macros | Merged: ALM `Generable`/content/schema as primitives, SwiftAgent `StructuredOutput`/resolver semantics preserved | ALM supplies local schema/content generation. SwiftAgent supplies agent-facing output registrations, transcript resolving, grounding, and UX behavior. |
| `@SessionSchema` | SwiftAgent, updated to emit local core types | This macro is a SwiftAgent agent-layer feature. It should remain canonical and stop emitting Apple `FoundationModels` references. |
| `@Generable / @Guide` | AnyLanguageModel | These macros belong with ALM's local `Generable`, `GenerationGuide`, and schema model and should be folded into SwiftAgent's macro target/API. |
| transport / HTTP client / replay | SwiftAgent | SwiftAgent's replay recorder, HTTP abstraction, network logging, and AgentRecorder workflow are core to provider parity and test review. ALM provider HTTP helpers should adapt to this direction rather than introduce a second long-term transport stack. |
| provider model identifiers | Merged, direct-provider-biased | Preserve ALM direct provider types and string/custom endpoint flexibility. Map SwiftAgent's current `OpenAIModel`, `AnthropicModel`, and `SimulationModel` defaults/convenience only where they remain useful. |
| provider capabilities | New merged capability model | Neither current stack fully owns the desired model. Implement the accepted hybrid: capability `OptionSet` checks, protocol inference, model/provider/runtime separation, and rich per-run streaming events. |

## Dependency Impact Notes

- No dependency changes are part of this planning phase.
- `JSONSchema` may become a base dependency if ALM schema builders/converters are moved into `Sources/SwiftAgent`. Alternative: preserve or extend SwiftAgent's existing schema conversion helpers. This requires explicit approval before `Package.swift` changes.
- `PartialJSONDecoder` may become a base dependency if Phase 3 adopts ALM's partial structured-output decoding for streaming snapshots. This should be decided with the streaming implementation plan, not in this planning-only phase.
- `swift-syntax` version and macro target shape will need reconciliation when `@Generable`/`@Guide` and `@SessionSchema` converge.
- `EventSource` version reconciliation is likely during provider migration because both packages use SSE support with different resolved versions.
- `async-http-client` should remain confined to the copied ALM package unless an approved optional transport path is retained. Long-term provider integration should prefer SwiftAgent `HTTPClient` and replay.
- `swift-transformers`, `mlx-swift-lm`, and `llama.swift` should not enter the base SwiftAgent product. If retained, they belong in optional provider targets/products in later phases.
- MacPaw `OpenAI` and `SwiftAnthropic` must remain until Phase 4/5 direct-provider replay parity is proven and a separate dependency removal proposal is approved.
- Any dependency removal or replacement from either package must be documented only until the user explicitly approves it. The proposal must include current users, replacement path, affected targets/products, and build/test evidence.

## Later Implementation Outline

After approval, implement in small vertical slices:

1. Introduce local core primitive ownership in SwiftAgent using ALM source as the starting point.
2. Update SwiftAgent protocols and macros to reference local core primitives instead of Apple `FoundationModels`.
3. Merge generated content stable encoding and schema conversion helpers into the canonical content/schema stack.
4. Define the merged transcript shape before migrating session streaming behavior.
5. Define the canonical `LanguageModelSession` API boundary while keeping provider replacement work out of Phase 2 implementation unless separately approved.
6. Adapt tests around compile-time core API behavior before removing old implementation paths.

This outline is not approval to implement. It only describes the expected sequence after review.

## Test And Build Plan For Later Implementation

Run after implementation changes, scaled to the files touched:

```bash
swiftformat --config ".swiftformat" <changed Swift files>
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" build -quiet
```

Additional focused tests expected as canonical types are merged:

- SwiftAgent macro tests for `@SessionSchema` output after removing Apple `FoundationModels` references.
- ALM core tests for `GeneratedContent`, conversion protocols, `GenerationSchema`, `DynamicGenerationSchema`, `GenerationGuide`, `Prompt`, `Instructions`, `ToolExecutionDelegate`, custom generation options, `@Generable`, and `@Guide`.
- SwiftAgent transcript codable/stable JSON tests.
- SwiftAgent prompt builder and transcript resolver tests.
- SwiftAgent tool schema and decodable tool tests.
- Simulated session tests as a provider-independent session behavior baseline.
- Replay recorder tests to ensure fixture formatting remains stable.

Provider replay tests should be preserved but not used to justify removing SDK adapters until Phase 4/5 provider parity work.

## Approval Gates

- This plan must be reviewed and approved before any Phase 2 implementation code changes.
- The proposed canonical source table must be approved concept by concept or amended before implementation.
- Any merged type whose canonical source is listed as "merged" needs explicit design acceptance before source replacement begins.
- Dependency additions, removals, or replacements require separate explicit approval.
- `Package.swift` changes require explicit approval.
- Moving, pruning, or renaming files under `External/AnyLanguageModel/` requires explicit approval.
- Removing Apple `FoundationModels` imports from SwiftAgent source is implementation work and must wait for approval.
- Removing MacPaw `OpenAI`, `SwiftAnthropic`, ALM dependencies, or copied ALM package metadata is out of scope until a later approved phase.
- Provider-specific session deprecation or deletion is out of scope until canonical session parity and replay evidence exist.
- Pause after creating this plan and wait for user review/approval before implementation.

## Rollback And Cleanup Notes

- Because this phase creates only a markdown plan, rollback is limited to removing or editing `plans/phase-2-canonical-types-plan.md`.
- If the proposed ownership table is rejected, update this plan rather than changing Swift source.
- If later implementation reveals that a chosen canonical source cannot preserve required behavior, stop and add a decision note before continuing.
- Keep `External/AnyLanguageModel/` intact until a later approved cleanup phase.
- Keep old SwiftAgent provider/session paths until direct provider parity and migration tests justify removal.

## Open Questions

- Should `GeneratedContent` stable JSON behavior live directly on the canonical ALM-derived type, or in a SwiftAgent replay/test helper extension?
- Should `Prompt` expose SwiftAgent source metadata publicly, package-internally, or through a transcript-only wrapper?
- Should `Instructions` become a top-level user value only, or should transcript instructions use a distinct nested representation with tool definitions?
- How should SwiftAgent `StructuredOutput` relate to `Generable`: should all structured outputs become `Generable`, or should `StructuredOutput.Schema` remain the generable payload?
- Should `ToolExecutionDelegate` survive as a delegate protocol, or should it become one hook inside a broader `ToolExecutionPolicy` value?
- What is the exact public shape of response/snapshot types: keep `AgentResponse`/`AgentSnapshot`, adopt ALM `LanguageModelSession.Response`/`ResponseStream.Snapshot`, or typealias/converge names?
- How should provider model identifiers balance typed convenience enums with direct provider string model IDs and custom endpoints?
- Which capability flags are required in the first implementation slice versus deferred to Phase 6 provider expansion?
- Should `JSONSchema` be adopted as a base dependency, or should SwiftAgent's schema conversion remain internal and dependency-light?
- Should partial structured decoding use `PartialJSONDecoder`, ALM's current `GeneratedContent(json:)` fallback behavior, or a SwiftAgent-specific reducer?
- How should `SystemLanguageModel` preserve optional Apple Foundation Models support without reintroducing Apple `FoundationModels` as a base conceptual dependency?
- What minimum source compatibility, if any, should be preserved for current `OpenAISession`, `AnthropicSession`, and `SimulatedSession` examples during convergence?
