# SwiftAgent Refactor Implementation Plan

## Ordering Rationale

The logical order is not to rewrite providers first. Providers cannot be cleanly migrated until the new `LanguageModel` turn contract exists.

The practical order is:

1. Inventory providers and current behavior.
2. Define new model-turn types and provider protocol.
3. Build shared `ConversationEngine`.
4. Migrate one provider end to end.
5. Build `LanguageModelSession` on the engine.
6. Build `AgentSession` on the engine.
7. Migrate remaining providers.
8. Update schema/docs/tests.

This still respects the provider-first concern: provider behavior drives the protocol design, but the protocol comes before wholesale provider migration.

## Phase 0: Baseline and Inventory

Deliverables:

- Provider behavior matrix.
- Current feature matrix from README.
- Failing/passing tests captured before refactor.
- Phase completion report: `AgentRefactor/results-phase0.md`, including what was completed and notes for Phase 1.

Tasks:

1. List every current provider and API variant:
   - OpenAI Chat Completions.
   - OpenAI Responses.
   - Open Responses compatible API.
   - Anthropic.
   - SimulatedSession.
2. For each provider, document:
   - Text generation.
   - Structured output.
   - Image input.
   - Tool calling.
   - Streaming text.
   - Streaming tool calls.
   - Reasoning.
   - Continuation requirements.
   - Usage/metadata support.
3. Record current tests that must survive:
   - Provider replay tests.
   - Session streaming tests.
   - Tool execution policy tests.
   - Transcript resolver tests.
   - Macro tests.
4. Mark current README examples that must move from `LanguageModelSession` to `AgentSession`.

Exit criteria:

- A checked-in provider/feature matrix.
- Agreement on which behaviors belong to `LanguageModelSession` vs `AgentSession`.

## Phase 1: Define Core Model-Turn Contract

Deliverables:

- New neutral request/response/event types.
- New `LanguageModel` protocol shape.
- Compatibility removed or isolated from current provider/session shape.
- Phase completion report: `AgentRefactor/results-phase1.md`, including what was completed and notes for Phase 2.

Tasks:

1. Add `ModelRequest`.
2. Add `ModelResponse`.
3. Add `ModelStreamEvent`.
4. Add `ModelTurnCompletion`.
5. Add `ProviderContinuation`.
6. Add provider-neutral `ToolChoice`:
   - automatic
   - none
   - required
   - named tool
7. Add `ToolDefinition` support for local SwiftAgent tools and provider-defined server-side tools.
8. Add `ToolCallPartial` and tool-input lifecycle types if existing stream event types are insufficient.
9. Add `ResponseFormat` if current structured output options need a clearer home.
10. Define `LanguageModel.respond(to:)`.
11. Define `LanguageModel.streamResponse(to:)`.
12. Move provider availability/capabilities onto the new protocol.
13. Expand `ModelStreamEvent` with a rich lifecycle taxonomy, using Vercel/Swift AI SDK as a reference:
   - text start/delta/end
   - reasoning start/delta/end
   - tool input start/delta/end
   - complete tool calls
   - provider-executed tool results
   - source/file events
   - warnings
   - usage/metadata/finish/raw/error

Exit criteria:

- New protocol compiles with a mock provider.
- No provider migration yet required except a minimal test fake.
- Unit tests cover model-turn type encoding/equality where needed.

## Phase 2: Build ConversationEngine

Deliverables:

- Shared internal state engine.
- Provider continuation state store.
- Model event reducer.
- Phase completion report: `AgentRefactor/results-phase2.md`, including what was completed and notes for Phase 3.

Tasks:

1. Add `ConversationEngine`.
2. Add `ConversationState`.
3. Add `ProviderContinuationStore`.
4. Add `ModelRequestBuilder`.
5. Add `TranscriptRecorder`.
6. Add `ModelEventReducer`.
7. Add `StructuredOutputAccumulator`.
8. Add usage and metadata accumulators.
9. Make prompt entries and prompt groundings flow through the engine.
10. Ensure provider-native continuation state is never reconstructed from public transcript if stored state exists.

Exit criteria:

- Engine can run a mock text turn.
- Engine can run a mock structured-output turn.
- Engine can reduce streaming text and structured deltas.
- Engine can preserve opaque provider continuation through a mock tool turn.
- Transcript resolver tests still pass against engine-produced transcript.

## Phase 3: Migrate One Provider End to End

Deliverables:

- One provider migrated end to end through the new engine.
- Provider replay coverage for reasoning/tool continuation.
- Phase completion report: `AgentRefactor/results-phase3.md`, including what was completed and notes for Phase 4.

Recommended first provider: OpenResponsesLanguageModel.

Reason:

- It is the provider that exposed the missing continuation abstraction.
- It validates reasoning plus function-call continuation.
- It isolates the Responses-compatible provider before migrating `OpenAILanguageModel`, which owns both Chat Completions and Responses variants and should be migrated as one unit later.

Tasks:

1. Rewrite provider to implement new `LanguageModel` protocol.
2. Convert request building to use `ModelRequest`.
3. Convert response parsing to return `ModelResponse`.
4. Convert streaming parser to return `ModelStreamEvent`.
5. Store raw Responses output items in `ProviderContinuation`.
6. Consume `ProviderContinuation` when tool outputs are present.
7. Port replay tests to assert:
   - reasoning item is replayed.
   - function call item is replayed.
   - function call output is appended.
   - final answer streams after continuation.

Exit criteria:

- One real provider passes text, structured output, streaming, reasoning, and tool continuation tests through the new engine.

## Phase 4: Rebuild LanguageModelSession

Deliverables:

- `LanguageModelSession` as stateful direct conversation API.
- No automatic tool execution.
- Phase completion report: `AgentRefactor/results-phase4.md`, including what was completed and notes for Phase 5.

Tasks:

1. Reimplement `LanguageModelSession` using `ConversationEngine`.
2. Keep API focused on direct model calls:
   - `respond`
   - `streamResponse`
   - structured output overloads
   - image overloads if supported by request types
3. Preserve Observation state:
   - `isResponding`
   - `transcript`
   - `tokenUsage`
   - `responseMetadata`
4. Support tool definitions in `LanguageModelSession` only for manual tool-call inspection.
5. Remove automatic tool execution from `LanguageModelSession`.
6. Update tests:
   - text response
   - structured response
   - streaming response
   - transcript state
   - token usage
   - metadata
   - schema resolution

Exit criteria:

- Direct LLM use cases from README work.
- `@SessionSchema` resolves `LanguageModelSession.transcript`.
- No tool execution loop exists in `LanguageModelSession`.

## Phase 5: Build AgentSession

Deliverables:

- Central non-streaming and streaming tool loop.
- Agent result/event API.
- Phase completion report: `AgentRefactor/results-phase5.md`, including what was completed and notes for Phase 6.

Tasks:

1. Add `AgentConfiguration`.
2. Add `AgentResult`.
3. Add `AgentStepResult` for first-class per-iteration history, following the `steps` concept in Vercel/Swift AI SDK.
4. Add `AgentEvent`.
5. Add `AgentSession`.
6. Implement `AgentSession` as `@unchecked Sendable` with locked mutable state, following the `LanguageModelSession` pattern.
7. Start with minimal `AgentConfiguration`:
   - `maxIterations`
   - `toolExecutionPolicy`
   - `stopOnToolError`
8. Implement max-iteration protection through an internal stop-policy evaluator so richer stop conditions can be added later without rewriting the loop.
9. Make `AgentSession` observable with durable state only:
   - `isRunning`
   - `transcript`
   - `tokenUsage`
   - `responseMetadata`
   - `currentIteration`
   - `currentToolCalls`
   - `currentToolOutputs`
   - `latestError`
10. Move tool execution loop into `AgentSession`.
11. Use `ConversationEngine` for every model turn.
12. Use `ProviderContinuation` for every continuation turn.
13. Support typed final output with `@Generable`.
14. Support streaming text, reasoning, partial tool calls, tool outputs, and final output.
15. Emit rich tool lifecycle events:
   - tool input started/delta/completed
   - approval requested
   - execution started
   - preliminary/output delta
   - execution completed
   - execution failed
16. Support request-building with an active-tool filter so each run/step can expose a subset of registered tools. Public API for this can wait if needed, but the engine/request builder should not assume all registered tools are always sent.
17. Preserve existing tool execution policy behavior.
18. Preserve `ToolRunRejection` behavior.
19. Add max-iteration protection.
20. Add cancellation behavior.
21. Keep multi-agent orchestration out of scope, but ensure `AgentSession.run` and `AgentSession.stream` are clean enough for a future orchestrator to call.

Exit criteria:

- Non-streaming tool loop works through `AgentSession`.
- Streaming tool loop works through `AgentSession`.
- `AgentResult` exposes per-step results.
- Agent streams expose tool lifecycle events needed for future approvals.
- Tool rejections are recoverable.
- Token usage aggregates across iterations.
- `@SessionSchema` resolves `AgentSession.transcript`.

## Phase 6: Migrate Remaining Providers

Deliverables:

- All existing providers implement the new `LanguageModel`.
- Phase completion report: `AgentRefactor/results-phase6.md`, including what was completed and notes for Phase 7.

Tasks:

1. Migrate `OpenAILanguageModel`, including both API variants:
   - Chat Completions.
   - Responses.
2. Migrate Anthropic.
3. Migrate `SimulatedSession` as a deterministic simulation provider.
4. For each provider, add replay/unit coverage for:
   - request serialization
   - response parsing
   - stream parsing
   - tool call parsing
   - continuation payload
   - reasoning payload if supported
5. Remove old provider methods that take `within session: LanguageModelSession`.

Exit criteria:

- No provider depends on `LanguageModelSession`.
- Providers do not execute tools.
- Existing provider replay tests pass in migrated form.

## Phase 7: Schema and Macro Alignment

Deliverables:

- Runtime-neutral schema naming and docs.
- Phase completion report: `AgentRefactor/results-phase7.md`, including what was completed and notes for Phase 8.

Tasks:

1. Rename `LanguageModelSessionSchema` to a runtime-neutral schema protocol.
2. Preferred name: `TranscriptSchema`.
3. Keep the `@SessionSchema` macro name unless there is a stronger reason to change the public macro.
4. Ensure macro-generated tools work with `AgentSession`.
5. Ensure macro-generated structured outputs work with both session types.
6. Ensure grounding metadata remains tied to prompts and transcript entries.
7. Update macro tests for both `LanguageModelSession` and `AgentSession`.

Exit criteria:

- `@SessionSchema` resolves transcripts from both public APIs.
- No schema type semantically depends on `LanguageModelSession`.

## Phase 8: Documentation Rewrite

Deliverables:

- README aligned with the new conceptual model through additive updates to existing sections.
- Example app updated to expose both direct conversation and agent execution paths.
- Phase completion report: `AgentRefactor/results-phase8.md`, including what was completed and notes for Phase 9.

Tasks:

1. Preserve existing README sections unless they are strictly obsolete; prefer updating and adding examples over removing documentation.
2. Introduce the three public concepts:
   - `LanguageModel`
   - `LanguageModelSession`
   - `AgentSession`
3. Move simple chat examples to `LanguageModelSession`.
4. Move tool execution examples to `AgentSession`.
5. Explain direct provider/model calls.
6. Explain transcript resolution applies to both session types.
7. Explain provider capabilities and unsupported features.
8. Document streaming:
   - direct conversation streaming
   - agent streaming
9. Document migration notes for internal app usage.
10. Update the example app OpenAI and Anthropic tabs with a navigation-bar menu for selecting:
   - `LanguageModelSession`, to validate direct model calls and manual tool-call inspection behavior.
   - `AgentSession`, to validate automatic tool execution and agent streaming behavior.

Exit criteria:

- README no longer describes `LanguageModelSession` as the agent loop owner.
- Tool execution examples use `AgentSession`.
- Schema docs mention both `LanguageModelSession` and `AgentSession`.
- Example app can exercise both LMS and AS paths for OpenAI and Anthropic.

## Phase 9: Cleanup and Hardening

Deliverables:

- Removed old architecture paths.
- Stable test coverage.
- AgentRecorder scenarios updated or verified against the new provider/session architecture.
- Phase completion report: `AgentRefactor/results-phase9.md`, including what was completed and final refactor notes.

Tasks:

1. Delete old provider/session APIs.
2. Remove duplicate streaming tool loops from providers.
3. Audit docs and comments for old terminology.
4. Run full tests.
5. Build all supported schemes.
6. Add regression tests for OpenAI Responses reasoning continuation.
7. Add architecture tests or compile-time checks that providers cannot access `AgentSession` or execute tools.
8. Update AgentRecorder scenarios that depend on old provider/session APIs.
9. Verify AgentRecorder can record the key direct and agent flows:
   - direct text/structured responses
   - direct streaming
   - agent streaming tool calls
   - Responses reasoning/tool continuation

Exit criteria:

- Full test suite passes.
- Example app builds.
- AgentRecorder builds or signing-only failure is documented.
- AgentRecorder scenarios are current for the refactored provider/session split.
- No provider owns an agent/tool loop.

## Current Feature Mapping

| Current Feature | Future Owner |
| --- | --- |
| Plain text response | `LanguageModelSession`, `AgentSession` |
| Structured output | `LanguageModel` serialization + `ConversationEngine` reduction + both public sessions |
| Prompt builder | Shared prompt/model request layer |
| Images | `ModelRequest` attachments + provider serialization |
| Transcript access | `ConversationEngine`, exposed by both sessions |
| Token usage | `ConversationEngine`, exposed by both sessions |
| Response metadata | `ConversationEngine`, exposed by both sessions |
| Reasoning summaries | Provider parser + `ConversationEngine` transcript reduction |
| Tool schema serialization | `LanguageModel` |
| Tool choice | `ModelRequest` + provider serialization; used by both sessions |
| Provider-defined tools | Provider serialization/parsing + `ConversationEngine` transcript reduction |
| Tool execution | `AgentSession` only |
| Tool execution policy | `AgentSession` |
| Tool filtering | Request builder/agent loop, with public API deferred if needed |
| Streaming text | Provider stream parser + `ConversationEngine` |
| Streaming tool calls | Provider stream parser + `AgentSession` loop |
| Tool lifecycle events | Provider stream parser + `AgentSession` event stream |
| Tool rejections | Tool engine + `AgentSession` |
| `@SessionSchema` | Transcript/schema layer, both sessions |
| Simulated sessions | Migrated deterministic `SimulatedSession` provider plus focused engine test fakes where useful |

## Explicit Non-Goals

This refactor should not implement:

- New external providers.
- Long-term memory.
- Vector retrieval.
- Handoffs.
- Multi-agent orchestration.
- Guardrails.
- Tool approvals UI.
- Workflow engines.

It should make those features possible without putting their logic into providers.
