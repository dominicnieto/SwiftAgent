# SwiftAgent Refactor Implementation Plan

Last verified: 2026-04-29.

## Current Status

Phases 1-7 are complete in the forked architecture.

The original plan used `ProviderContinuation`. This fork replaced that with provider metadata preserved directly on public model/transcript values. Do not reintroduce `ProviderContinuation` while continuing phase 8 unless the public API design is deliberately reopened.

Current layering:

```text
AgentSession
  -> LanguageModelSession
  -> ConversationEngine
  -> LanguageModel
```

## Phase 0: Baseline and Inventory

Status: complete.

Deliverables:

- Provider behavior matrix.
- README feature matrix.
- Baseline tests/builds captured.
- Phase completion report: `AgentRefactor/results-phase0.md`.

## Phase 1: Define Core Model-Turn Contract

Status: complete.

Final deliverables:

- `ModelRequest`
- `ModelMessage`
- `ModelAttachment`
- `ModelResponse`
- `ModelStreamEvent`
- `ModelTurnCompletion`
- `ToolChoice`
- `ToolDefinition`
- `ToolDefinitionKind`
- `ModelToolCall`
- `ToolInputStart`
- `ToolCallPartial`
- `ResponseFormat`
- `StructuredOutputRequest`
- public `LanguageModel.respond(to:)`
- public `LanguageModel.streamResponse(to:)`

Fork correction:

- `ProviderContinuation` was removed.
- Provider-specific continuity state is preserved through `providerMetadata`.

## Phase 2: Build ConversationEngine

Status: complete.

Final deliverables:

- Package-internal `ConversationEngine` actor.
- Request builder from transcript/prompt/tools/tool outputs/options.
- Transcript recorder.
- Model event reducer.
- Structured output accumulator.
- Usage and metadata accumulators.
- Prompt grounding preservation.
- Streaming snapshot reduction.

Fork correction:

- There is no `ProviderContinuationStore`.
- Continuation fidelity depends on provider metadata carried through transcript/model values.

## Phase 3: Migrate One Provider End to End

Status: complete.

Completed first provider:

- `OpenResponsesLanguageModel`

Exit criteria met:

- Text, structured output, streaming, reasoning, tool-call parsing, tool-output continuation, usage, metadata, and provider replay tests pass through the neutral turn contract.

Fork correction:

- Raw Responses items and IDs are preserved through provider metadata and raw provider output, not a separate continuation object.

## Phase 4: Rebuild LanguageModelSession

Status: complete.

Final behavior:

- `LanguageModelSession` owns `ConversationEngine`.
- Direct `respond` and `streamResponse` remain public low-level APIs.
- Tool definitions can be passed for manual tool-call inspection.
- Local tools are not executed.
- Explicit continuation APIs exist:
  - `respond(with toolOutputs:)`
  - `streamResponse(with toolOutputs:)`
- Observation state, transcript, token usage, response metadata, structured output, images, prompts, groundings, and schema overloads are preserved.

## Phase 5: Build AgentSession

Status: complete.

Final behavior:

- `AgentSession` owns a `LanguageModelSession`.
- Non-streaming and streaming tool loops work through LMS runtime hooks.
- Local tool execution, retries, missing-tool handling, `ToolRunRejection`, max iterations, per-step history, typed results, and agent events live in `AgentSession`.
- Provider-defined/server-side tool calls are not executed locally.

Fork correction:

- `AgentSession` no longer shares `ConversationEngine` directly with `LanguageModelSession`.

## Phase 6: Migrate Remaining Providers

Status: complete.

Migrated providers:

- `OpenAILanguageModel` Chat Completions.
- `OpenAILanguageModel` Responses.
- `OpenResponsesLanguageModel`.
- `AnthropicLanguageModel`.
- `SimulationLanguageModel`.

Exit criteria met:

- Providers implement the neutral `LanguageModel` turn contract.
- Providers do not depend on `LanguageModelSession`.
- Providers do not execute local tools.
- Provider replay tests pass in migrated form.

## Phase 7: Schema and Macro Alignment

Status: complete.

Final behavior:

- Runtime-neutral schema protocol is `TranscriptSchema`.
- `LanguageModelSessionSchema` is removed.
- Public macro remains `@SessionSchema`.
- Macro-generated tools and structured outputs work with `AgentSession`.
- Grounding metadata remains tied to prompt transcript entries.
- Schema resolution works from both `LanguageModelSession.transcript` and `AgentSession.transcript`.

## Phase 8: Documentation and Example App Rewrite

Status: next.

Deliverables:

- README aligned with the current public API stack.
- Example app exposes both direct model/session calls and agent execution paths.
- Phase completion report: `AgentRefactor/results-phase8.md`.

Tasks:

1. Preserve useful existing README content, but correct ownership:
   - `LanguageModel`: one-turn model backend.
   - `LanguageModelSession`: stateful low-level inference/session API.
   - `AgentSession`: high-level automatic tool-loop runtime.
2. Move simple chat, structured output, prompt builder, image input, provider options, and manual tool-call inspection docs to `LanguageModelSession`.
3. Move automatic tool execution, tool retries/rejections, multi-step token usage, and agent event streaming docs to `AgentSession`.
4. Document direct `LanguageModel` use and the provider-metadata rule:
   - direct use works for one turn;
   - provider metadata must be preserved by callers who manually build multi-turn state and need provider-native fidelity.
5. Document `store` behavior for OpenAI Responses:
   - SwiftAgent omits `store` unless set;
   - OpenAI Responses defaults to stored behavior;
   - `store: false` requires preserving/requesting encrypted reasoning metadata for full reasoning continuity.
6. Document provider feature gaps by linking to the provider `FEATURE_PARITY.md` files.
7. Explain direct streaming vs agent streaming:
   - `LanguageModelSession.streamResponse(...)` streams one model turn/session response.
   - `AgentSession.stream(...)` streams model events plus tool lifecycle events across loop iterations.
8. Update schema docs to say `@SessionSchema` resolves shared transcript values from both public session APIs.
9. Update ExampleApp OpenAI and Anthropic flows with a mode selector:
   - `LanguageModelSession`
   - `AgentSession`
10. Add `AgentRefactor/results-phase8.md` with verification commands and remaining phase-9 work.

Exit criteria:

- README no longer describes `LanguageModelSession` as the agent loop owner.
- Tool execution examples use `AgentSession`.
- Direct low-level model/session examples use `LanguageModelSession` or `LanguageModel`.
- Schema docs mention both public session types.
- Example app can exercise both LMS and AgentSession paths for OpenAI and Anthropic.

## Phase 9: Cleanup and Hardening

Status: completed. See `AgentRefactor/results-phase9.md`.

Tasks:

1. Audit source comments/docs for old architecture terms.
2. Add provider feature tests from the new provider matrices where appropriate.
3. Add OpenAI Responses first-class provider options:
   - `previousResponseId`
   - `conversation`
   - `include`
   - automatic `reasoning.encrypted_content` include when needed.
4. Expand hosted/server tool coverage where prioritized:
   - OpenAI web search/file search/code interpreter.
   - Anthropic web search/fetch/code execution/memory/container/context management.
6. Verify AgentRecorder scenarios against direct and agent flows.
7. Run full SwiftPM and Xcode verification.

Exit criteria:

- Full test suite passes.
- Example app builds.
- AgentRecorder builds.
- Provider docs/matrices match implemented behavior.
- No provider owns an agent/tool loop.
