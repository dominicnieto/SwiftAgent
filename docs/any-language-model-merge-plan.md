# AnyLanguageModel Merge Plan

## Direction

This is an absorb-and-converge migration. AnyLanguageModel is moved into SwiftAgent and its useful primitives/providers become SwiftAgent's canonical model layer. The final architecture should not contain a bridge between two independent model stacks.

The final API should be clean rather than compatibility-driven. There are no existing app consumers, so migration should prefer the canonical `LanguageModelSession(model:tools:instructions:)` shape over preserving `OpenAISession` or `AnthropicSession`.

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
- Test coverage checklist.
- Initial list of source-compatible APIs worth preserving.

## Phase 1: Move Source Into Repo

Goals:

- Bring the whole AnyLanguageModel repo into SwiftAgent as first-class repo content.
- Avoid semantic changes during the initial move.
- Reduce the chance of missing source, tests, scripts, fixtures, documentation, or package metadata.

Tasks:

- Create `plans/phase-1-copy-any-language-model-plan.md`.
- Copy the entire AnyLanguageModel repository into SwiftAgent mechanically with shell copy commands.
- Do not rewrite files by hand during the initial move.
- Preserve the copied repo layout first, including sources, tests, package files, docs, scripts, fixtures, and metadata.
- Build the copied package in place before changing SwiftAgent to use it.
- After the copied repo builds, start pruning or relocating files intentionally.
- Add required package dependencies currently used by AnyLanguageModel only after the copied source is present and the dependency needs are clear.

Notes:

- This phase may temporarily expose AnyLanguageModel as a separate target to keep the move reviewable.
- That target separation is organizational scaffolding, not the final architecture.
- The final public API should be folded into SwiftAgent.
- Prefer reviewable mechanical commits/patches: copy first, compile, then refactor.

## Phase 2: Choose Canonical Core Types

Goals:

- Remove duplicate type definitions by selecting one canonical implementation for each core concept.
- Get approval for canonical type choices before implementation.

Approval gate:

- Create `plans/phase-2-canonical-types-plan.md`.
- Before editing implementation code, produce a summary of each duplicate concept and the proposed canonical source.
- Wait for approval before replacing or merging the types.

Example approval table:

```text
Concept               Proposed canonical source
Generable             AnyLanguageModel
GeneratedContent      AnyLanguageModel
GenerationSchema      AnyLanguageModel
Tool                  AnyLanguageModel
GenerationOptions     AnyLanguageModel
Transcript            merged, SwiftAgent-biased
LanguageModelSession  merged, AnyLanguageModel provider boundary + SwiftAgent agent state
```

Canonical starting points:

- Use AnyLanguageModel for `Generable`, `GeneratedContent`, `GenerationSchema`, `Prompt`, `Instructions`, `Tool`, `LanguageModel`, and `GenerationOptions`.
- Use a merged transcript biased toward SwiftAgent's current agent transcript.
- Use a merged `LanguageModelSession` that combines AnyLanguageModel's provider boundary with SwiftAgent's transcript, token usage, schema, and streaming requirements.

Tasks:

- Replace SwiftAgent's Apple FoundationModels imports with local core imports.
- Update SwiftAgent protocols and macros to reference local core primitives.
- Merge duplicate helpers around generated content and schema conversion.
- Keep compatibility typealiases only where they do not hide duplicate implementations.

Exit criteria:

- SwiftAgent core no longer requires Apple FoundationModels.
- Tool and structured output constraints use local core types.

## Phase 3: Merge Transcript and Streaming

Goals:

- Create one transcript model that works for FoundationModels-style usage and agent-grade UX.
- Upgrade streaming to be transcript-first.
- Add replay-friendly transcript versioning, diffing, and structured-output source tracking.

Tasks:

- Create `plans/phase-3-transcript-streaming-plan.md`.
- Add `instructions` and `image` support to the SwiftAgent-style transcript.
- Preserve `reasoning`, `status`, `callId`, structured segment type/source, grounding metadata, and transcript resolution.
- Define internal model update events.
- Define public snapshots with content, raw content, transcript, and token usage.
- Move snapshot throttling into the canonical session engine.
- Treat provider streaming gaps as priority blockers, not follow-up polish.
- Add tests for transcript upsert behavior and final snapshot completeness.
- Add transcript schema version and focused diff helpers for fixture review.
- Track structured output source as provider-native, prompt-fallback, or constrained-decoder.

Exit criteria:

- Streaming snapshots are derived from transcript/token state.
- Tool calls and tool outputs are visible during streaming.
- Content-only snapshot streams are no longer the provider contract for agent-capable providers.

## Phase 4: Replace OpenAI Provider Path

Goals:

- Remove the OpenAI SDK implementation path.
- Route OpenAI generation through the direct AnyLanguageModel provider code.
- Preserve `OpenAILanguageModel` and `OpenResponsesLanguageModel` as distinct providers.

Tasks:

- Create `plans/phase-4-openai-provider-plan.md`.
- Move both `OpenAILanguageModel` and `OpenResponsesLanguageModel` into SwiftAgent's provider area.
- Do not merge them into one provider unless a later design decision explicitly chooses that.
- Map current SwiftAgent OpenAI model names and defaults.
- Fold `OpenAIGenerationOptions` into canonical `GenerationOptions` custom options.
- Upgrade OpenAI streaming provider events to emit transcript and token updates.
- Surface normalized provider metadata, warnings, rate-limit details, and retry-after hints where OpenAI provides them.
- Port OpenAI request/response fixture tests.
- Delete or deprecate `OpenAIAdapter` once parity is proven.

Exit criteria:

- OpenAI text, structured output, tool calling, streaming, token usage, and reasoning tests pass through the direct provider path.
- Package no longer needs MacPaw/OpenAI for OpenAI behavior.
- OpenAI provider streaming emits transcript-first updates, including tool call argument deltas and reasoning events where available.

## Phase 5: Replace Anthropic Provider Path

Goals:

- Remove the SwiftAnthropic implementation path.
- Route Anthropic generation through the direct AnyLanguageModel provider code.

Tasks:

- Create `plans/phase-5-anthropic-provider-plan.md`.
- Merge `AnthropicLanguageModel` into the provider area.
- Map current SwiftAgent Anthropic model names and defaults.
- Fold `AnthropicGenerationOptions` into canonical `GenerationOptions` custom options.
- Upgrade Anthropic streaming provider events to emit transcript and token updates.
- Preserve thinking/reasoning behavior and validation rules.
- Surface normalized provider metadata, warnings, rate-limit details, and retry-after hints where Anthropic provides them.
- Port Anthropic request/response fixture tests.
- Delete or deprecate `AnthropicAdapter` once parity is proven.

Exit criteria:

- Anthropic text, structured output, tool calling, streaming, token usage, and reasoning tests pass through the direct provider path.
- Package no longer needs SwiftAnthropic.
- Anthropic provider streaming emits transcript-first updates, including tool use JSON deltas and thinking/signature deltas where available.

## Phase 6: Integrate Additional Providers

Goals:

- Make the non-OpenAI/non-Anthropic AnyLanguageModel providers available through the same canonical session and transcript model.
- Keep Apple Foundation Models support through `SystemLanguageModel`.

Tasks:

- Create `plans/phase-6-additional-providers-plan.md`.
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

## Phase 7: Cleanup and API Polish

Goals:

- Remove migration scaffolding and update public documentation.

Tasks:

- Create `plans/phase-7-cleanup-api-polish-plan.md`.
- Delete unused adapter protocols and provider SDK helpers.
- Delete duplicate transcript/session/option types.
- Update README and examples.
- Add migration notes for users of old `OpenAISession` and `AnthropicSession`.
- Consolidate logging around SwiftAgent's existing `AgentLog`, `NetworkLog`, and replay recorder direction.
- Add redaction hooks for credentials and sensitive tool outputs.
- Run full supported-platform builds and tests.

Exit criteria:

- One canonical model/session/transcript stack remains.
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
