# Phase 3 Additional Providers Skeleton Plan

## Phase Goal

Port the next provider or provider family into SwiftAgent's main model stack without reintroducing a parallel AnyLanguageModel subsystem.

Phase 3 should finish one provider at a time from start to finish: source move, SwiftAgent integration, transcript-first streaming, tool policy, replay fixtures, provider-specific tests, docs/examples where relevant, and dependency decisions. Do not split a provider into tiny type-only slices that leave the architecture half-bridged.

## Carry-Forward Rules From Phase 2

- Mechanical copy is a reviewability tactic, not architecture.
- When bringing a whole ALM file over, mechanically copy/move it first where possible, then do targeted SwiftAgent edits.
- After copy, absorb and converge: provider code must use SwiftAgent's main `LanguageModel`, `LanguageModelSession`, `Transcript`, `GenerationOptions`, `ToolExecutionPolicy`, `HTTPClient`, replay, and logging paths.
- Do not create interim protocols, placeholder types, bridge sessions, adapter shims, or compatibility-only typealiases to avoid connected work.
- Do not stop at a small slice. A provider is not Phase 3-done until it has durable feature parity and tests.
- Keep provider tests grouped under `Tests/SwiftAgentTests/Providers/<ProviderName or ProviderFamily>/` when the file count grows.
- Use replay-backed tests as the default. Live-network tests may inform parity, but they should not be the required unit test path.
- Preserve existing user-facing functionality unless there is an explicit removal decision.

## Source Docs To Read First

- `docs/provider-capability-streaming-reference.md`
- `docs/streaming-provider-gaps-spec.md`
- `docs/merge-test-matrix.md`
- `docs/package-layout-spec.md`
- `docs/dependency-migration-plan.md`
- `docs/any-language-model-merge-decisions.md`
- Phase 2 implementation/results docs for current provider patterns:
  - `docs/phase-2-completion-checklist.md`
  - `docs/phase-2-canonical-types-results.md`

## Provider Workstream Template

For each provider, complete these before moving to the next provider:

1. Choose the provider and confirm dependency approval needs.
2. Audit ALM source/tests for that provider and identify source files to mechanically copy/move.
3. Copy/move whole files where practical, then refactor onto SwiftAgent's main APIs.
4. Implement provider request building through `SwiftAgent.HTTPClient`, not ALM `HTTPSession`.
5. Implement non-streaming text, structured output, image/multimodal support where the provider supports it, options, custom options, metadata, errors, and token usage.
6. Implement transcript-first streaming according to the streaming gap spec: text deltas, structured deltas, tool-call deltas, reasoning if supported, metadata, token usage, finish status, warnings/errors.
7. Route tool calls through `LanguageModelSession` tool execution policy; providers emit calls and consume outputs, the session executes tools.
8. Add provider capabilities that match actual implemented behavior.
9. Add replay fixtures/tests for request shape, text, structured output, streaming text, streaming structured output, tool calls, tool-call streaming, metadata, token usage, and error mapping as applicable.
10. Update AgentRecorder scenarios only when provider parity is ready enough to record useful fixtures.
11. Update docs/results and mark dependency decisions clearly.

## Current Provider Foundation To Reuse

Phase 2 established the pattern for OpenAI, Open Responses, Anthropic, and Simulation:

- Provider types live in `Sources/SwiftAgent/Providers/`.
- Provider replay tests live in `Tests/SwiftAgentTests/Providers/`.
- Shared replay helper lives in `Tests/SwiftAgentTests/Helpers/ReplayHTTPClient.swift`.
- Provider source should conform directly to `LanguageModel`.
- Public sessions should be `LanguageModelSession(model:tools:instructions:)`.
- Streaming snapshots should be derived from transcript/session state, not provider-private state.
- Partial structured streaming should use the approved `PartialJSONDecoder` path when needed.
- JSON request/response construction should use the approved `JSONSchema` / `JSONValue` path where it naturally fits.
- AsyncHTTPClient remains optional via SwiftPM trait and must not become a base dependency.

## Likely Phase 3 Provider Candidates

The planning agent should choose ordering deliberately. Candidate providers from ALM include:

- `GeminiLanguageModel`
- `OllamaLanguageModel`
- `SystemLanguageModel`
- `CoreMLLanguageModel`
- `MLXLanguageModel`
- `LlamaLanguageModel`

Cloud/lightweight providers may live in the base `SwiftAgent` target if their dependencies stay light. Heavy or platform-sensitive local providers should use optional products/targets per `docs/package-layout-spec.md`.

## Approval Gates

Explicit approval is still required before:

- removing dependencies from `External/AnyLanguageModel`
- pruning or deleting `External/AnyLanguageModel`
- adding MLX, Llama, CoreML, or other heavy optional-provider dependencies to the base `SwiftAgent` target
- adding new base-target dependencies that change default build weight
- removing public APIs beyond already approved Phase 2 removals

For any dependency decision, record:

- current users
- replacement path
- affected targets/products
- validation evidence
- whether the dependency is removed, retained, trait-gated, or moved to an optional target

## Test And Build Expectations

Minimum validation per provider:

```bash
swiftformat --config ".swiftformat" <changed Swift files>
swift test --filter <ProviderName>
swift test
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet
```

Run broader app/recorder builds when public package surface, examples, AgentRecorder, or provider recording flows change:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet
```

## Results Doc

Create a Phase 3 results doc when implementation starts, for example:

```text
docs/phase-3-additional-providers-results.md
```

Record provider-by-provider:

- files copied/moved
- files refactored
- commands/results
- fixture sources
- gaps against the capability/streaming specs
- dependency decisions
- follow-ups

## Open Questions For Planning Agent

- Which provider should go first, and why?
- Which providers are light enough for base `SwiftAgent`, and which require optional targets/products?
- Should Gemini/Ollama be completed before local heavy providers to keep Phase 3 momentum?
- What replay fixture strategy is needed for each provider before code changes start?
- Which ALM provider tests can be mechanically copied first, then rewritten onto SwiftAgent replay?
