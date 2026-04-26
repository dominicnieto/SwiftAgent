# AnyLanguageModel Merge Plan

## Direction

This is an absorb-and-converge migration. AnyLanguageModel is moved into SwiftAgent and its useful primitives/providers become SwiftAgent's main model layer. The final architecture should not contain a bridge between two independent model stacks.

The final API should be clean rather than compatibility-driven. There are no existing app consumers, so migration should prefer the main `LanguageModelSession(model:tools:instructions:)` shape over preserving `OpenAISession` or `AnthropicSession`.

## Phase Planning Requirement

Before implementing any phase, create a dedicated phase plan/spec file in `plans/`.

The phase plan should translate these higher-level docs into concrete steps for that phase only. It should include:

- phase goal
- source docs read
- scope and non-goals
- files/areas expected to change
- implementation steps
- test/build commands
- approval gates
- rollback or cleanup notes
- open questions

Do not start implementation for a phase until its `plans/phase-*-*.md` file exists.

Every phase must also produce a phase results doc in `docs/`. The results doc should record what actually happened: commands run, build/test results, failures, skipped validation, changed files/directories, dependency decisions made or deferred, and follow-ups for later phases.

Every phase plan must explicitly call out dependency changes. If a phase proposes removing a dependency from either SwiftAgent's package or the copied AnyLanguageModel package, summarize the dependency, the reason for removal, the replacement path, and the test/build evidence, then wait for explicit approval before removing it.

## Phase 0: Inventory and Baseline

Goals:

- Record current SwiftAgent public API shape.
- Record AnyLanguageModel public API shape.
- Identify tests that must continue to pass or be intentionally rewritten.

Tasks:

- Create `plans/phase-0-inventory-plan.md`.
- Create the inventory output doc at `docs/phase-0-inventory.md`.
- Inventory all `import FoundationModels` usage.
- Inventory all OpenAI and Anthropic SDK usage.
- Inventory duplicate types between the repos.
- Capture current SwiftAgent streaming behavior with tests or replay fixtures.
- Capture AnyLanguageModel provider coverage.

Outputs:

- `docs/phase-0-inventory.md`.
- `docs/phase-0-results.md` if Phase 0 execution details are not already captured in the inventory doc.
- Test coverage checklist.
- Initial list of source-compatible APIs worth preserving.

## Phase 1: Move Source Into Repo

Goals:

- Bring the whole AnyLanguageModel repo into SwiftAgent as first-class repo content.
- Avoid semantic changes during the initial move.
- Reduce the chance of missing source, tests, scripts, fixtures, documentation, or package metadata.

Tasks:

- Create `plans/phase-1-copy-any-language-model-plan.md`.
- Create `docs/phase-1-copy-results.md`.
- Copy the entire AnyLanguageModel repository into SwiftAgent mechanically with shell copy commands.
- Do not rewrite files by hand during the initial move.
- Preserve the copied repo layout first, including sources, tests, package files, docs, scripts, fixtures, and metadata.
- Build the copied package in place before changing SwiftAgent to use it.
- Record the exact copy/build commands, results, and any failures in `docs/phase-1-copy-results.md`.
- Do not prune, relocate, rename modules, merge types, integrate providers, or migrate dependencies in Phase 1.
- Defer pruning, relocation, SwiftAgent integration, and dependency migration to later approved phases.

Notes:

- This phase may temporarily expose AnyLanguageModel as a separate target to keep the move reviewable.
- That target separation is organizational scaffolding, not the final architecture.
- The final public API should be folded into SwiftAgent.
- Prefer reviewable mechanical commits/patches: copy first, compile, then refactor.

## Phase 2: Core Model Stack Merge

Goals:

- Replace the current split Phase 2/3/4/5 plan with one coherent model-stack merge.
- Build whole features across their natural boundaries instead of stopping at artificial phase lines.
- Converge core primitives, `GenerationOptions`, `LanguageModel`, `LanguageModelSession`, transcript/streaming, tool execution, OpenAI, and Anthropic as one architecture.
- Preserve SwiftAgent's agent-grade transcript, replay, token usage, logging, and schema behavior while absorbing AnyLanguageModel's direct provider stack.
- Avoid interim protocols, placeholder types, bridge sessions, or compatibility-only abstractions that would be removed later.

Planning requirement:

- Use `plans/phase-2-canonical-types-plan.md`.
- Do not create separate Phase 3/4/5 plans for transcript/streaming/OpenAI/Anthropic; those are now workstreams inside this phase.

Architecture rule:

- If an ALM type naturally depends on another ALM architectural type, move or design the related type with it.
- Do not introduce a smaller temporary protocol, typealias, wrapper, adapter, or placeholder only to keep an old phase boundary intact.
- If a feature cannot be completed coherently in the current change, defer the whole feature or split it by durable product behavior, not by dependency avoidance.
- Compatibility wrappers are acceptable only when they are thin convenience APIs over the main implementation and have a clear removal or permanence decision.

Feature-complete workstreams:

- **Primary core and options:** `Generable`, `GeneratedContent`, `GenerationSchema`, `DynamicGenerationSchema`, `GenerationGuide`, `Prompt`, `Instructions`, `Tool`, `Availability`, `GenerationOptions`, `JSONValue`, and provider-specific custom options compile through SwiftAgent's public API.
- **Provider/session boundary:** `LanguageModel` and `LanguageModelSession(model:tools:instructions:)` become the real provider/session boundary. Existing `LanguageModelProvider`, `Adapter`, `OpenAISession`, and `AnthropicSession` may remain only as compatibility conveniences over the main engine or be removed once tests and examples move.
- **Transcript and streaming:** the merged transcript supports instructions, prompts, reasoning, tool calls, tool output, responses, images, structured output source tracking, stable IDs, token usage outside transcript entries, replay-friendly coding, and snapshots derived from transcript/token state.
- **Tool execution:** providers emit tool calls; the session owns execution policy, approval hooks, parallelism, retry/missing-tool behavior, and tool output transcript updates.
- **OpenAI direct provider:** `OpenAILanguageModel` and `OpenResponsesLanguageModel` replace the MacPaw SDK path for text, structured output, tool calling, streaming, reasoning, metadata, and replay fixture coverage.
- **Anthropic direct provider:** `AnthropicLanguageModel` replaces the SwiftAnthropic path for text, structured output, tool calling, streaming thinking/reasoning, metadata, and replay fixture coverage.
- **Public package/API surface:** `import SwiftAgent` exposes the main core API through a `SwiftAgent` library product. Provider-session products may remain only as compatibility conveniences after parity decisions.
- **AgentRecorder/examples/docs:** AgentRecorder and examples use the merged session/provider API once the provider paths are ready.

Tasks:

- Finish convergence of local core primitives already started in the earlier main-type work.
- Add `JSONSchema` and `PartialJSONDecoder` when moved ALM code needs them. These dependency additions are approved for this merged phase; dependency removals still require separate approval.
- Move `GenerationOptions` with its real `LanguageModel` relationship rather than introducing an interim custom-options provider protocol.
- Design and implement the main `LanguageModel`/`LanguageModelSession` surface before wiring provider-specific option and request paths that depend on it.
- Merge transcript and streaming reducers before declaring direct providers migrated.
- Replace OpenAI and Anthropic provider paths through direct ALM-derived providers only when transcript-first streaming, tool calls, structured output, token usage, metadata, and replay coverage are present.
- Remove or deprecate old SDK adapter paths only after parity is proven and dependency removal is explicitly approved.
- Keep heavy optional providers out of the base product unless separately approved.
- Add the public `SwiftAgent` library product as part of exposing the main API.

Exit criteria:

- SwiftAgent core no longer requires Apple FoundationModels.
- `GenerationOptions`, `LanguageModel`, `LanguageModelSession`, transcript/streaming, OpenAI, and Anthropic are coherent parts of one stack.
- Streaming snapshots are derived from transcript/token state.
- Tool calls and tool outputs are visible during streaming.
- Content-only snapshot streams are no longer the provider contract for agent-capable providers.
- OpenAI text, structured output, tool calling, streaming, token usage, and reasoning tests pass through the direct provider path.
- OpenAI provider streaming emits transcript-first updates, including tool call argument deltas and reasoning events where available.
- Anthropic text, structured output, tool calling, streaming, token usage, and reasoning tests pass through the direct provider path.
- Anthropic provider streaming emits transcript-first updates, including tool use JSON deltas and thinking/signature deltas where available.
- Package dependency removal proposals for MacPaw/OpenAI and SwiftAnthropic have explicit approval and evidence before removal.
- `import SwiftAgent` exposes the main core API.
- README/examples use the main merged session API.

Implementation results for earlier main-type work are recorded in `docs/phase-2-canonical-types-results.md`.

## Phase 3: Integrate Additional Providers

Goals:

- Make the non-OpenAI/non-Anthropic AnyLanguageModel providers available through the same main session and transcript model.
- Keep Apple Foundation Models support through `SystemLanguageModel`.

Tasks:

- Create `plans/phase-3-additional-providers-plan.md`.
- Integrate `SystemLanguageModel` / Apple Foundation Models.
- Integrate Gemini, Ollama, MLX, CoreML, Llama, and other OpenResponses-compatible providers.
- Keep the core API folded into `SwiftAgent`.
- Put heavy local providers behind separate optional provider targets/products, such as `SwiftAgentMLX` and `SwiftAgentLlama`.
- Use SwiftPM traits only where they genuinely simplify conditional dependencies.
- Verify provider-specific custom options.
- Add hybrid provider capability metadata where behavior differs:
  - Conduit-style model/provider/runtime capability separation.
  - Swarm-style `OptionSet` flags and protocol inference.
  - Swift AI SDK-style rich streaming event enum for provider-to-session updates.
- Use `docs/streaming-provider-gaps-spec.md` as the provider streaming parity checklist.

Exit criteria:

- Optional providers compile under intended platform/dependency conditions.
- Provider differences are expressed through capabilities/options, not separate session architectures.

## Phase 4: Cleanup and API Polish

Goals:

- Remove migration scaffolding and update public documentation.

Tasks:

- Create `plans/phase-4-cleanup-api-polish-plan.md`.
- Delete unused adapter protocols and provider SDK helpers.
- Delete duplicate transcript/session/option types.
- Update README and examples.
- Add migration notes for users of old `OpenAISession` and `AnthropicSession`.
- Consolidate logging around SwiftAgent's existing `AgentLog`, `NetworkLog`, and replay recorder direction.
- Add redaction hooks for credentials and sensitive tool outputs.
- Run full supported-platform builds and tests.

Exit criteria:

- One main model/session/transcript stack remains.
- Public examples demonstrate the merged API.
- Build and test commands pass.

## Validation Checklist

- Build SDK iOS simulator.
- Build AgentRecorder macOS.
- Build SwiftAgentTests.
- Run SwiftAgentTests.
- Run macro tests.
- Run any moved AnyLanguageModel tests that do not require live credentials.
- Run replay fixture tests for provider request/response behavior.
- Swift-format changed Swift files.
