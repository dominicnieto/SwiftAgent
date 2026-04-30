# Phase 8 Handoff

Last verified: 2026-04-29.

## Current Architecture

Phases 1-7 are complete in the forked architecture:

```text
AgentSession
  -> LanguageModelSession
  -> ConversationEngine
  -> LanguageModel
```

`ProviderContinuation` is not part of this fork. Provider-native state is preserved through `providerMetadata` on model/transcript values and raw provider output.

## Verified Current State

- `LanguageModel` is public and is the lowest-level model backend.
- `LanguageModelSession` is the low-level stateful inference/session API.
- `LanguageModelSession` owns `ConversationEngine`.
- `LanguageModelSession` does not execute local tools.
- `LanguageModelSession` supports explicit tool-output continuation:
  - `respond(with toolOutputs:)`
  - `streamResponse(with toolOutputs:)`
- `AgentSession` owns `LanguageModelSession`.
- `AgentSession` owns local tool execution, loop policy, max iterations, and agent events.
- Providers implement the neutral `LanguageModel` turn API and do not depend on `LanguageModelSession`.
- `@SessionSchema` resolves shared transcript data from both public sessions through `TranscriptSchema`.
- Provider feature/parity matrices exist beside provider implementations.

## Provider Source Layout

- `Sources/SwiftAgent/Providers/OpenAI/`
- `Sources/SwiftAgent/Providers/OpenResponses/`
- `Sources/SwiftAgent/Providers/Anthropic/`
- `Sources/SwiftAgent/Providers/Shared/`
- `Sources/SimulatedSession/Simulation/`

## Phase 8 Work

Use `AgentRefactor/ImplementationPlan.md` and `AgentRefactor/readme-feature-matrix.md` as the source of truth.

Phase 8 should:

- Rewrite README conceptual sections around:
  - `LanguageModel`
  - `LanguageModelSession`
  - `AgentSession`
- Move automatic tool execution examples to `AgentSession`.
- Keep direct text, structured output, image input, prompt builder, streaming, provider options, and manual tool-call inspection examples on `LanguageModelSession`.
- Document direct `LanguageModel` use and provider metadata preservation for manual multi-turn state.
- Document OpenAI `store` behavior:
  - SwiftAgent omits `store` unless set.
  - OpenAI Responses stores by default.
  - `store: false` may require encrypted reasoning metadata for full reasoning continuity.
- Link provider feature gaps to the provider `FEATURE_PARITY.md` files.
- Update ExampleApp OpenAI/Anthropic flows with a mode selector for:
  - `LanguageModelSession`
  - `AgentSession`
- Add `AgentRefactor/results-phase8.md` after implementation and verification.

## Current Verification

Last full verification before this handoff:

- `swift test` passed with 142 tests.
- `xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet` passed.
- `xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" build -quiet` passed.
- `xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet` passed.
- `git diff --check` passed.
- `swiftformat` could not run because it is not installed in this environment.

