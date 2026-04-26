# Phase 2 Canonical Types And Core Model Stack Plan

## Phase Goal

Merge the SwiftAgent and AnyLanguageModel model stacks into one coherent implementation.

The original version of this plan chose canonical type ownership. That inventory and ownership table remain authoritative, but Phase 2 is no longer limited to isolated core-type slices. Phase 2 now includes the connected model-stack work needed to avoid temporary architecture: `GenerationOptions`, `LanguageModel`, `LanguageModelSession`, transcript-first streaming, tool execution policy, direct OpenAI provider parity, and direct Anthropic provider parity.

Build whole durable features across their natural boundaries. Do not introduce interim protocols, placeholder types, bridge sessions, adapter shims, or compatibility-only typealiases just to satisfy an artificial phase boundary. If an ALM type depends on `LanguageModel`, `LanguageModelSession`, `Transcript`, `GenerationOptions`, provider requests, or streaming events, move or design the connected pieces together.

## Source Docs Read

- `docs/any-language-model-merge-plan.md`
- `docs/any-language-model-merge-spec.md`
- `docs/any-language-model-merge-decisions.md`
- `docs/dependency-migration-plan.md`
- `docs/package-layout-spec.md`
- `docs/phase-0-inventory.md`
- `docs/phase-1-copy-results.md`
- `docs/phase-2-canonical-types-results.md`
- `docs/phase-2-completion-checklist.md`
- `docs/provider-capability-streaming-reference.md`
- `docs/streaming-provider-gaps-spec.md`
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
- Merge `GenerationOptions` and `JSONValue` with the real ALM `LanguageModel` relationship.
- Design and implement canonical `LanguageModel`.
- Design and implement canonical `LanguageModelSession(model:tools:instructions:)`.
- Merge transcript and streaming behavior into a transcript-first session engine.
- Move direct ALM OpenAI and Anthropic provider implementations into SwiftAgent.
- For OpenAI and Anthropic, satisfy the Phase 2 provider capability and streaming acceptance criteria in `docs/provider-capability-streaming-reference.md` and `docs/streaming-provider-gaps-spec.md`.
- Fold provider-specific options into canonical `GenerationOptions` custom options.
- Move AgentRecorder, examples, and docs to the merged API when provider parity is ready.
- Define approval gates for dependency removals and optional providers.

## Non-Goals

- Do not integrate optional heavy providers into the base product in this phase.
- Do not add MLX, Llama, CoreML, or AsyncHTTPClient to the base SwiftAgent target unless separately approved.
- Do not remove MacPaw `OpenAI` or `SwiftAnthropic` until direct-provider parity is proven and dependency removal is explicitly approved.
- Do not prune `External/AnyLanguageModel` until the corresponding moved code is verified and cleanup is approved.
- Do not preserve old provider-specific sessions as parallel architectures.

## Files And Areas Expected To Change

Implementation will likely touch these areas:

- `Sources/SwiftAgent/`: local core primitives, transcript, token usage, response/snapshot models, prompt/instructions, tool protocols, schema protocols, provider/session API, transport integration hooks.
- `Sources/SwiftAgent/LanguageModelProvider/`: replacement or collapse of `LanguageModelProvider`, `Adapter`, and provider update APIs into the canonical `LanguageModelSession` engine.
- `Sources/SwiftAgent/Models/`: merged `Transcript`, `AgentResponse`/`AgentSnapshot` or canonical response/snapshot shapes, `TokenUsage`, structured-output snapshot behavior.
- `Sources/SwiftAgent/Protocols/`: convergence of remaining adapter/session/schema protocols around local `Generable`, `GeneratedContent`, `GenerationSchema`, and `Tool`.
- `Sources/SwiftAgent/Prompting/`: reconciliation of SwiftAgent prompt source metadata with AnyLanguageModel `Prompt` and `Instructions`.
- `Sources/SwiftAgent/Networking/`: keep SwiftAgent `HTTPClient`, `HTTPReplayRecorder`, `NetworkLog`, and SSE helpers as the long-term transport/replay direction.
- `Sources/SwiftAgentMacros/`: keep `@SessionSchema` expansions on local core types and align generated resolver code with the final merged transcript/session API.
- `Sources/OpenAISession/`, `Sources/AnthropicSession/`, `Sources/SimulatedSession/`: later migration or deprecation of provider-specific session/adapters once canonical `LanguageModelSession` can preserve behavior.
- `AgentRecorder/AgentRecorder/`: later migration from provider-specific sessions and SDK imports to canonical session/direct provider APIs.
- `Examples/` and `Sources/ExampleCode/`: later import/API updates after the canonical public surface exists.
- `External/AnyLanguageModel/Sources/AnyLanguageModel/`: source material for core primitives and provider implementations. Files should remain unmoved during this planning phase.
- `External/AnyLanguageModel/Sources/AnyLanguageModelMacros/`: source material for `@Generable` and `@Guide` macros.
- `Tests/SwiftAgentTests/`, `Tests/SwiftAgentMacroTests/`, and `External/AnyLanguageModel/Tests/AnyLanguageModelTests/`: later adaptation of SwiftAgent behavior tests and ALM core tests into the merged API.
- `Package.swift`: add the public `SwiftAgent` product, add approved dependencies when needed, and edit provider products/dependencies only after parity and approval gates are satisfied.
- `README.md`: later migration from old `OpenAISession`/`AnthropicSession` and Apple `FoundationModels` examples to the canonical `SwiftAgent` API.

## Reverified Starting State

Reverified on April 25, 2026 while converting this plan to the broader Phase 2 definition:

- SwiftAgent source/test/example/AgentRecorder paths no longer contain `FoundationModels` imports.
- SwiftAgent already owns local primitive files for `GeneratedContent`, `Generable`, `GenerationSchema`, `DynamicGenerationSchema`, `GenerationGuide`, `GenerationID`, `Instructions`, `Tool`, `Availability`, and the generated-content conversion protocols.
- SwiftAgent macros already include ALM-derived `@Generable` and `@Guide` implementations, and `@SessionSchema` emits local `SwiftAgent.Tool`.
- Focused carry-forward tests exist for conversion, dynamic schema, guide, prompt, instructions, availability, decodable tool schema, macro expansion, and defaulted-property parity.
- SwiftAgent does not yet own canonical `GenerationOptions`, `JSONValue`, `LanguageModel`, or `LanguageModelSession`.
- OpenAI, Anthropic, and Simulated provider paths still use the old `AdapterGenerationOptions` / provider-specific options architecture.
- No direct OpenAI or Anthropic ALM providers have been migrated into the canonical SwiftAgent session stack.
- `Package.swift` does not yet expose a `.library(name: "SwiftAgent", targets: ["SwiftAgent"])` product; public products are still provider-session shaped.
- `README.md` still documents the old provider-session API and includes Apple `FoundationModels` imports.

The already completed primitive work should remain credited as carry-forward work, but it must not be treated as completing the broader Phase 2 model-stack workstreams.

## Duplicate Concept Inventory

- Core generated content: SwiftAgent now owns an ALM-derived local `GeneratedContent`, conversion protocols, stable IDs, JSON conversion, and partial JSON support for the completed primitive slice; broader session/provider use still needs convergence.
- Schema and generability: SwiftAgent now owns ALM-derived local `Generable`, `GenerationSchema`, `DynamicGenerationSchema`, `GenerationGuide`, and related macro wiring for the completed primitive slice; broader provider/session schema behavior still needs convergence.
- Prompting: SwiftAgent has prompt builder/source metadata for transcript resolving; AnyLanguageModel has FoundationModels-style `Prompt`, `PromptBuilder`, `PromptRepresentable`, `Instructions`, and `InstructionsBuilder`.
- Tooling: SwiftAgent now owns local `Tool` and keeps `SwiftAgentTool` / `DecodableTool` ergonomics; AnyLanguageModel also has argument/output conversion, schema injection, and `ToolExecutionDelegate` behavior still to reconcile with session-owned tool policy.
- Session/provider boundary: SwiftAgent uses `LanguageModelProvider`, `Adapter`, `AdapterUpdate`, provider-specific sessions, and SDK adapters; AnyLanguageModel uses `LanguageModel` providers plus `LanguageModelSession(model:tools:instructions:)`.
- Generation options: SwiftAgent has provider-specific `OpenAIGenerationOptions`, `AnthropicGenerationOptions`, and simulation options; AnyLanguageModel has one `GenerationOptions` with common fields and model-specific custom options.
- Transcript: SwiftAgent has agent-grade prompt/reasoning/tool/response entries, status, call IDs, upsert, resolved transcript APIs, and stable JSON helpers; AnyLanguageModel adds instructions entries, image segments, prompt options, response formats, and tool definitions.
- Streaming: SwiftAgent streams transcript/token updates and derives snapshots; AnyLanguageModel streams content/raw-content snapshots and appends transcript after completion in several paths.
- Token usage: SwiftAgent has public `TokenUsage` and accumulation outside transcript; AnyLanguageModel does not provide equivalent agent-grade token usage as a canonical session/snapshot concern.
- Structured output: SwiftAgent has `StructuredOutput`, `DecodableStructuredOutput`, `@SessionSchema`, transcript resolving, and UX snapshots; AnyLanguageModel has `@Generable`, `@Guide`, `StructuredGeneration`, and partial structured decoding.
- Observation/session UI state: SwiftAgent provider sessions are `@Observable` and expose transcript/token state for UI use; AnyLanguageModel's `LanguageModelSession` is `@Observable` and exposes `isResponding` plus transcript.
- Transport/replay/logging: SwiftAgent has replay-aware `HTTPClient`, `HTTPReplayRecorder`, `NetworkLog`, and `AgentLog`; AnyLanguageModel has URLSession/AsyncHTTPClient helpers and provider-local request helpers.
- Public package surface: the target architecture requires `import SwiftAgent`, but current package products are still `OpenAISession`, `AnthropicSession`, and `ExampleCode`.
- Provider identities/capabilities: SwiftAgent has typed provider model enums per SDK adapter; AnyLanguageModel has direct providers and mostly string model IDs, but the target architecture needs explicit capability metadata.
- Provider metadata/rate limits/warnings: SwiftAgent has logging/replay surfaces for request and network metadata; provider replacement needs normalized request IDs, provider model IDs, warnings, retry hints, and rate-limit details outside transcript.
- Optional provider dependencies: AnyLanguageModel includes CoreML, MLX, Llama, and AsyncHTTPClient dependency paths that affect canonicalization boundaries but are not core runtime types.
- Transcript replay/diff: SwiftAgent replay fixtures and transcript codable tests need stable encoding; the merge docs also require transcript schema versioning and focused diff helpers.
- Structured output source tracking: merged structured output must identify provider-native, prompt-fallback, or constrained-decoder output paths.
- Reasoning representation: SwiftAgent has a dedicated reasoning transcript entry with summary, encrypted reasoning payload, and status; this must not collapse into normal assistant text.

## Proposed Canonical Sources

| Concept | Proposed canonical source | Rationale |
| --- | --- | --- |
| `Generable` | AnyLanguageModel | ALM already provides the local FoundationModels-style replacement required to remove Apple `FoundationModels` imports. SwiftAgent should consume this directly instead of keeping a wrapper. |
| `GeneratedContent` | AnyLanguageModel, with SwiftAgent stable encoding behavior preserved | ALM owns the local content model and conversion protocols. SwiftAgent's stable JSON behavior must be folded in because replay fixtures and transcript codable tests depend on deterministic output. |
| `GenerationSchema` | AnyLanguageModel, with SwiftAgent provider JSON-schema conversion behavior preserved | ALM supplies the local schema representation and conversion tests. SwiftAgent's OpenAI/Anthropic schema mapping expectations remain required until provider parity replaces SDK adapters. |
| `DynamicGenerationSchema` | AnyLanguageModel | ALM already has a local dynamic schema model and tests; SwiftAgent now owns the ALM-derived primitive and should continue folding broader schema/session behavior into that local stack. |
| `GenerationGuide` | AnyLanguageModel | ALM's guide model pairs with `@Guide`, `Generable`, and schema generation, so it should move with that stack. |
| `Prompt` | Merged, AnyLanguageModel-biased public type with SwiftAgent source metadata retained | ALM should provide the FoundationModels-style prompt builder shape. SwiftAgent must keep input/source metadata needed for transcript resolving, grounding, and replay/debuggability. |
| `Instructions` | AnyLanguageModel, extended for SwiftAgent transcript requirements | ALM has the canonical local instructions builder and transcript instructions entry. SwiftAgent needs this added without losing tool definition visibility. |
| `Tool` | AnyLanguageModel, with SwiftAgent `DecodableTool` ergonomics folded in where useful | ALM's tool protocol is already local, schema-aware, and model-session oriented. SwiftAgent's decodable tool and rejection/reporting behavior should become helpers or conformances around the canonical tool model. |
| `ToolExecutionDelegate / tool execution policy` | Merged, session-owned, SwiftAgent-biased policy semantics plus ALM delegate hook | ALM has a delegate hook, but merge docs require policy controls for parallel execution, retries, missing tools, failures, and approval. Providers should emit calls; canonical session should execute policy. |
| `LanguageModel` | AnyLanguageModel | ALM's `LanguageModel` is the desired direct provider boundary and enables replacing SDK adapters without a permanent bridge. |
| `LanguageModelSession` | Merged: ALM construction/provider boundary plus SwiftAgent state, transcript, streaming, token usage, schema, replay, and tool policy | The public API should prefer `LanguageModelSession(model:tools:instructions:)`, but ALM's current session is not agent-grade enough. SwiftAgent's transcript-first stream processing and token/state behavior must be built into the canonical session engine. |
| `GenerationOptions` | AnyLanguageModel, with SwiftAgent provider-specific options folded into custom options | The accepted decision is one common options type with model-specific custom options. This removes provider-specific session API pressure while preserving OpenAI/Anthropic power. |
| `Transcript` | Merged, SwiftAgent-biased with ALM additions | SwiftAgent's reasoning, call IDs, status, upsert, resolved transcript, and stable fixture behavior are mandatory. Reasoning remains its own transcript entry. Add ALM instructions, image segments, prompt options/response format, and tool definitions. |
| streaming events / snapshots | Merged, SwiftAgent-biased transcript-first model | SwiftAgent's `AdapterUpdate.transcript` and `AdapterUpdate.tokenUsage` model matches the target direction. ALM content-only snapshots are insufficient; retain ALM `content`/`rawContent` convenience in public snapshots while adding transcript and token usage. |
| `TokenUsage` | SwiftAgent | SwiftAgent already models input/output/total/cached/reasoning usage and accumulates it outside transcript. This aligns with accepted decisions. |
| structured output protocols/macros | Merged: ALM `Generable`/content/schema as primitives, SwiftAgent `StructuredOutput`/resolver semantics preserved | ALM supplies local schema/content generation. SwiftAgent supplies agent-facing output registrations, transcript resolving, grounding, and UX behavior. The merged model must track whether structured output came from provider-native support, prompt fallback, or constrained decoding. |
| `@SessionSchema` | SwiftAgent, aligned with the merged session/transcript API | This macro is a SwiftAgent agent-layer feature. It already emits local core type constraints and should remain canonical while generated resolver code follows the final merged transcript/session model. |
| `@Generable / @Guide` | AnyLanguageModel | These macros belong with ALM's local `Generable`, `GenerationGuide`, and schema model and should be folded into SwiftAgent's macro target/API. |
| transport / HTTP client / replay | SwiftAgent | SwiftAgent's replay recorder, HTTP abstraction, network logging, and AgentRecorder workflow are core to provider parity and test review. Direct providers should use `SwiftAgent.HTTPClient` as their provider transport. `URLSessionHTTPClient` remains the default implementation. ALM's optional `AsyncHTTPClient` capability should be absorbed as an optional SwiftAgent `HTTPClient` implementation in a separate target/product, not as the base transport and not through ALM's `HTTPSession` typealias. |
| provider model identifiers | Merged, direct-provider-biased | Preserve ALM direct provider types and string/custom endpoint flexibility. Map SwiftAgent's current `OpenAIModel`, `AnthropicModel`, and `SimulationModel` defaults/convenience only where they remain useful. |
| provider capabilities | New merged capability model | Neither current stack fully owns the desired model. Implement the accepted hybrid: capability `OptionSet` checks, protocol inference, model/provider/runtime separation, and rich per-run streaming events. |
| Observation / session UI state | Merged | Preserve ALM's canonical `@Observable LanguageModelSession` shape with `isResponding` and transcript, plus SwiftAgent's observable transcript/token usage behavior for agent UIs. |
| Provider metadata / rate limits / warnings | New merged metadata model outside transcript | Provider request IDs, normalized model IDs, warnings, rate-limit state, and retry-after hints are execution metadata. They should be available to responses, snapshots, logs, and replay without becoming model-visible transcript content. |
| Optional provider dependencies | SwiftAgent package-layout decision, not a core type | Optional providers affect canonicalization boundaries but are not runtime core types. MLX, CoreML, Llama, and similar dependencies should stay out of the base product and move only through later approved optional target/product work. |
| Transcript replay / diff | SwiftAgent-biased merged transcript support | Preserve deterministic replay review, stable generated-content JSON, transcript schema versioning, and focused diff helpers as canonical transcript infrastructure. |
| Structured output source tracking | Merged structured output behavior | Track whether structured output was produced by provider-native structured output, prompt fallback parsing, or constrained decoding so tests and debugging can distinguish reliability/failure modes. |
| Reasoning representation | SwiftAgent transcript behavior | Reasoning remains separate from normal assistant response text and must preserve summary, `encryptedReasoning`, and status where providers support them. |

## Dependency Impact Notes

- `JSONSchema` is approved for this phase when moving ALM `GenerationOptions`, `JSONValue`, direct providers, provider request builders, custom option payloads, or provider-neutral schema conversion into SwiftAgent. Do not rewrite ALM JSON/schema handling just to avoid this dependency.
- `PartialJSONDecoder` is approved for this phase when moving structured streaming or partial structured-output snapshots. It does not replace transcript-first streaming reducers, provider event parsing, tool-call streaming, token usage, or structured-output source tracking.
- `swift-syntax` version and macro target shape will need reconciliation when `@Generable`/`@Guide` and `@SessionSchema` converge.
- `EventSource` version reconciliation is likely during provider migration because both packages use SSE support with different resolved versions.
- `async-http-client` should not enter the base SwiftAgent target. The approved Phase 2 transport decision is to keep `SwiftAgent.HTTPClient` as the provider-facing transport, keep `URLSessionHTTPClient` as the default implementation, and add AsyncHTTPClient support only as an optional adapter target/product that conforms to `SwiftAgent.HTTPClient`.
- `swift-transformers`, `mlx-swift-lm`, and `llama.swift` should not enter the base SwiftAgent product. If retained, they belong in optional provider targets/products in a later provider phase.
- MacPaw `OpenAI` and `SwiftAnthropic` must remain until direct-provider replay parity is proven and separate dependency-removal approval is granted.
- Any dependency removal or replacement from either package must include current users, replacement path, affected targets/products, and build/test evidence before approval.

## Feature Workstreams

### Core And Options

- Keep ALM-derived `Generable`, `GeneratedContent`, `GenerationSchema`, `DynamicGenerationSchema`, `GenerationGuide`, `GenerationID`, `Instructions`, `Prompt`, `Tool`, and `Availability` as SwiftAgent-owned public primitives.
- Move `JSONValue` as the `JSONSchema.JSONValue` typealias rather than hand-rolling JSON infrastructure.
- Move `GenerationOptions` with its actual `LanguageModel` custom-options constraint.
- Fold `OpenAIGenerationOptions` and `AnthropicGenerationOptions` into model-specific custom option types.
- Preserve SwiftAgent stable JSON and provider schema normalization behavior.
- Expose the canonical core through a `SwiftAgent` library product.

### LanguageModel And Session

- Make ALM-style `LanguageModel` the provider boundary.
- Make `LanguageModelSession(model:tools:instructions:)` the canonical session engine.
- Preserve SwiftAgent observable transcript, cumulative token usage, replay/logging hooks, structured-output registration, and transcript resolver integration.
- Keep `OpenAISession`, `AnthropicSession`, and `LanguageModelProvider` only if they are thin compatibility conveniences over the canonical session.

### Transcript And Streaming

- Merge ALM transcript additions into SwiftAgent's agent-grade transcript.
- Preserve prompt, reasoning, tool calls, tool output, response status, stable IDs, call IDs, grounding/source metadata, and resolved transcript APIs.
- Add instructions, images, prompt response format/options, structured-output source tracking, schema versioning, and focused diff helpers.
- Providers emit rich events; the session reduces those events into transcript/token state.
- Public stream snapshots are derived from transcript/token state and include content, raw content, transcript, and token usage.
- `docs/provider-capability-streaming-reference.md` and `docs/streaming-provider-gaps-spec.md` are Phase 2 acceptance sources for OpenAI and Anthropic transcript-first streaming. They become Phase 3 guidance for later providers.

### Provider Capabilities And Metadata

- Implement the hybrid capability model from `docs/provider-capability-streaming-reference.md` for OpenAI and Anthropic Phase 2 parity: model/provider/runtime separation, `ProviderCapabilities` `OptionSet` checks, protocol inference, and explicit capability reporting where provider/model behavior differs.
- Use rich provider stream events for text, structured output, tool input deltas, completed tool calls/results, reasoning, metadata, token usage, raw chunks, warnings, finish status, and errors.
- Capabilities validate unsupported requests before dispatch where possible; warnings are reserved for unsupported settings or degradation paths that still produce a valid response.
- Provider metadata, request IDs, provider model IDs, rate-limit details, retry-after hints, and warnings remain execution metadata available to responses, snapshots, logs, and replay. They must not become model-visible transcript content.
- Tests must assert that providers emit the events promised by their capabilities and fail or degrade explicitly for unsupported capabilities.

### Tool Execution

- Providers emit tool calls and consume tool outputs.
- The session owns tool execution policy, parallel execution, retry policy, missing-tool behavior, failure behavior, and optional approval hooks.
- Tool calls and tool outputs must be visible during streaming.

### OpenAI Direct Provider

- Move `OpenAILanguageModel` and `OpenResponsesLanguageModel` into SwiftAgent.
- Preserve them as distinct providers unless a later design decision says otherwise.
- Adapt request building to SwiftAgent transport/replay/logging.
- Do not leave copied ALM `HTTPSession`, `Transport.swift`, or URLSession-only provider helpers as the final direct-provider transport. Mechanical copy is a reviewability tactic; copied provider code must be absorbed into SwiftAgent's `HTTPClient`, transcript, session, tool policy, replay, and logging architecture.
- Emit transcript-first streaming updates for text, structured output, tool calls, reasoning, token usage, metadata, warnings, and rate-limit details where available.
- Implement OpenAI capability reporting, warnings/errors, and rich stream event normalization according to `docs/provider-capability-streaming-reference.md` and the OpenAI/Open Responses sections of `docs/streaming-provider-gaps-spec.md`.
- Port replay-backed OpenAI tests before considering the provider path migrated.

### Anthropic Direct Provider

- Move `AnthropicLanguageModel` into SwiftAgent.
- Adapt request building to SwiftAgent transport/replay/logging.
- Do not leave copied ALM `HTTPSession`, `Transport.swift`, or URLSession-only provider helpers as the final direct-provider transport. Mechanical copy is a reviewability tactic; copied provider code must be absorbed into SwiftAgent's `HTTPClient`, transcript, session, tool policy, replay, and logging architecture.
- Preserve thinking/reasoning validation and streaming behavior.
- Emit transcript-first streaming updates for text, structured output, tool use JSON deltas, thinking/signature deltas, token usage, metadata, warnings, and rate-limit details where available.
- Implement Anthropic capability reporting, warnings/errors, and rich stream event normalization according to `docs/provider-capability-streaming-reference.md` and the Anthropic Messages section of `docs/streaming-provider-gaps-spec.md`.
- Port replay-backed Anthropic tests before considering the provider path migrated.

## Test And Build Plan For Implementation

Run after implementation changes, scaled to the files touched:

```bash
swiftformat --config ".swiftformat" <changed Swift files>
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" build -quiet
```

Additional focused tests expected as canonical types are merged:

- SwiftAgent macro tests for `@SessionSchema` output after the merged transcript/session API lands.
- ALM core tests for `GeneratedContent`, conversion protocols, `GenerationSchema`, `DynamicGenerationSchema`, `GenerationGuide`, `Prompt`, `Instructions`, `ToolExecutionDelegate`, custom generation options, `@Generable`, and `@Guide`.
- SwiftAgent transcript codable/stable JSON tests.
- SwiftAgent prompt builder and transcript resolver tests.
- SwiftAgent tool schema and decodable tool tests.
- Simulated session tests as a provider-independent session behavior baseline.
- Replay recorder tests to ensure fixture formatting remains stable.

Provider replay tests should be preserved and expanded before removing SDK adapters.

## Approval Gates

- The canonical source table must be followed unless explicitly amended.
- Any merged type whose canonical source is listed as "merged" needs design acceptance before replacement begins.
- `JSONSchema` and `PartialJSONDecoder` additions are approved for the connected Phase 2 work when needed.
- Dependency removals or replacements require separate explicit approval.
- Moving, pruning, or renaming files under `External/AnyLanguageModel/` requires explicit approval.
- Removing MacPaw `OpenAI`, `SwiftAnthropic`, ALM dependencies, or copied ALM package metadata requires explicit approval after parity evidence.
- Provider-specific session deprecation or deletion requires canonical session parity and replay evidence.

## Rollback And Cleanup Notes

- If the proposed ownership table is rejected, update this plan rather than changing Swift source.
- If implementation reveals that a chosen canonical source cannot preserve required behavior, stop and revise the design before adding compatibility scaffolding.
- If a temporary compatibility wrapper is introduced, document whether it is a permanent convenience or the exact condition for removal.
- Keep `External/AnyLanguageModel/` intact until cleanup is approved.
- Keep old SwiftAgent provider/session paths until canonical session parity and migration tests justify removal.

## Open Questions

- Should `GeneratedContent` stable JSON behavior live directly on the canonical ALM-derived type, or in a SwiftAgent replay/test helper extension?
- Should `Prompt` expose SwiftAgent source metadata publicly, package-internally, or through a transcript-only wrapper?
- Should `Instructions` become a top-level user value only, or should transcript instructions use a distinct nested representation with tool definitions?
- How should SwiftAgent `StructuredOutput` relate to `Generable`: should all structured outputs become `Generable`, or should `StructuredOutput.Schema` remain the generable payload?
- Should `ToolExecutionDelegate` survive as a delegate protocol, or should it become one hook inside a broader `ToolExecutionPolicy` value?
- What is the exact public shape of response/snapshot types: keep `AgentResponse`/`AgentSnapshot`, adopt ALM `LanguageModelSession.Response`/`ResponseStream.Snapshot`, or typealias/converge names?
- Resolved transport decision: AsyncHTTPClient support survives as an optional SwiftAgent transport adapter target/product, not as a base dependency and not as the provider-facing transport abstraction. Direct providers use `SwiftAgent.HTTPClient`; the optional adapter supplies a server-oriented implementation of that protocol.
- How should provider model identifiers balance typed convenience enums with direct provider string model IDs and custom endpoints?
- Which capability flags are required in the first implementation slice versus deferred to Phase 3 provider expansion?
- Should `JSONSchema` remain visible through public API surfaces beyond the `JSONValue` typealias, or stay an implementation dependency where possible?
- Should partial structured decoding use `PartialJSONDecoder`, ALM's current `GeneratedContent(json:)` fallback behavior, or a SwiftAgent-specific reducer?
- How should `SystemLanguageModel` preserve optional Apple Foundation Models support without reintroducing Apple `FoundationModels` as a base conceptual dependency?
- What minimum source compatibility, if any, should be preserved for current `OpenAISession`, `AnthropicSession`, and `SimulatedSession` examples during convergence?
