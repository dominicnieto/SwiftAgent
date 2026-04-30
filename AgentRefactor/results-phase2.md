# Phase 2 Results

Completed on 2026-04-27.

## Completed

- Read the Phase 2 planning inputs:
  - `AgentRefactor/Architecture.md`
  - `AgentRefactor/ComponentSpec.md`
  - `AgentRefactor/ImplementationPlan.md`
  - `AgentRefactor/provider-behavior-matrix.md`
  - `AgentRefactor/readme-feature-matrix.md`
  - `AgentRefactor/results-phase0.md`
  - `AgentRefactor/results-phase1.md`
- Added shared engine infrastructure in `Sources/SwiftAgent/LanguageModel/ConversationEngine.swift`:
  - `ConversationEngine`
  - `ConversationState`
  - `ModelRequestBuilder`
  - `TranscriptRecorder`
  - `ModelEventReducer`
  - `StructuredOutputAccumulator`
  - `TokenUsageAccumulator`
  - `ResponseMetadataAccumulator`
  - `ConversationStreamSnapshot`
- Kept the new runtime package-scoped, actor-isolated, and additive. Existing `LanguageModelSession` and provider paths still use the Phase 1 compatibility surface until later migration phases.
- Implemented model request building from the public transcript, instructions, filtered local tool definitions, structured output policy, attachments, and opaque continuation state.
- Preserved prompt entries and prompt grounding payloads through the engine-produced transcript.
- Preserved provider-native state through transcript/model provider metadata and passed that metadata into later requests.
- Implemented non-streaming response application into transcript, token usage, response metadata, tool calls, and reasoning.
- Implemented stream-event reduction for text deltas, structured deltas, reasoning entries, streamed tool-input lifecycle events, partial/completed tool calls, provider tool results, usage, metadata, completion, and warnings.
- Stream failures now terminate the engine stream with the provider error instead of being converted into response warnings.
- Stream cancellation now cancels the engine's provider-draining task when the downstream consumer stops iterating.
- `ConversationEngine` does not use `Locked` or `@unchecked Sendable`; mutable engine state is isolated by the actor.
- Streamed tool-input lifecycle and completed tool-call events are reconciled by logical provider call identity (`callId ?? id`) so a completed call with a different event id replaces the in-progress call instead of duplicating it.
- Added focused Swift Testing coverage in `Tests/SwiftAgentTests/Core/ConversationEngineTests.swift` for:
  - mock text turn transcript/usage/metadata recording,
  - mock structured-output turn and schema prompt injection,
  - streaming text reduction and completion,
  - streaming structured-delta reduction,
  - stream failure propagation,
  - streamed tool-input lifecycle transcript updates,
  - streamed tool-input/completed-call reconciliation when event id and call id differ,
  - downstream cancellation propagation,
  - provider metadata preservation through a mock tool turn,
  - transcript resolver compatibility for engine-produced grounded prompts.

## Verification

Commands run:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/ConversationEngineTests -derivedDataPath .tmp/DerivedData-phase2-engine test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -derivedDataPath .tmp/DerivedData-phase2-tests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" -derivedDataPath .tmp/DerivedData-phase2-example build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS,arch=arm64" -derivedDataPath .tmp/DerivedData-phase2-recorder build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/ConversationEngineTests -derivedDataPath .tmp/DerivedData-phase2-engine-2 test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -derivedDataPath .tmp/DerivedData-phase2-tests-final test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -derivedDataPath .tmp/DerivedData-phase2-tests-rerun2 test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" -derivedDataPath .tmp/DerivedData-phase2-example-rerun2 build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS,arch=arm64" -derivedDataPath .tmp/DerivedData-phase2-recorder-rerun2 build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/ConversationEngineTests -derivedDataPath .tmp/DerivedData-phase2-review-fixes test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -derivedDataPath .tmp/DerivedData-phase2-review-tests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" -derivedDataPath .tmp/DerivedData-phase2-review-example build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS,arch=arm64" -derivedDataPath .tmp/DerivedData-phase2-review-recorder build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/ConversationEngineTests -derivedDataPath .tmp/DerivedData-phase2-actor-engine test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -derivedDataPath .tmp/DerivedData-phase2-actor-tests test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" -derivedDataPath .tmp/DerivedData-phase2-actor-example build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS,arch=arm64" -derivedDataPath .tmp/DerivedData-phase2-actor-recorder build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/ConversationEngineTests -derivedDataPath .tmp/DerivedData-phase2-dedupe-engine test -quiet
swiftformat --config ".swiftformat" Sources/SwiftAgent/LanguageModel/ConversationEngine.swift Tests/SwiftAgentTests/Core/ConversationEngineTests.swift
git diff --check
```

Result:

- `ConversationEngineTests`: passed.
- `SwiftAgentTests`: passed.
- `ExampleApp` iOS simulator build: passed.
- `AgentRecorder` macOS build: passed.
- `git diff --check`: passed.
- `swiftformat`: could not run because `swiftformat` is not installed or available on `PATH` in this workspace (`zsh: command not found: swiftformat`).

## Notes For Phase 3

- The engine currently uses the neutral `LanguageModel.respond(to:)` and `LanguageModel.streamResponse(to:)` APIs. Real providers are still on the legacy session-shaped methods until Phase 3 migrates the first provider.
- Fork update: `ProviderContinuation` was removed. `ModelRequestBuilder` carries public transcript messages and provider metadata. Providers migrating in Phase 3 should preserve needed Responses/Anthropic payload details in metadata-bearing model/transcript values.
- The request builder serializes transcript tool calls into neutral message metadata as a bridge for later provider migration. The provider-specific wire formats should still be implemented inside providers, not inside the engine.
- `ModelEventReducer` stores streamed reasoning deltas but records reasoning transcript entries only from provider-completed reasoning events. If the first migrated provider needs synthesized reasoning entries from start/delta/end events, add that in the reducer with provider replay coverage.
- Phase 3 should start with `OpenResponsesLanguageModel` as planned and validate that raw Responses output items/IDs are preserved through provider metadata, then consumed on tool-output turns through `ConversationEngine`.
- When `LanguageModelSession`/`AgentSession` migrate to the actor-isolated engine, keep any public synchronous observation state in the public session layer rather than adding locks back to the engine.

## 2026-04-29 Verification Update

- Phase 2 remains complete in the metadata-based fork.
- Current `ConversationEngine` is package-internal, actor-isolated, and has no separate continuation store.
