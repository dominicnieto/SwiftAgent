# Phase 1 Results

Completed on 2026-04-27.

## Completed

- Read the Phase 1 planning inputs:
  - `AgentRefactor/Architecture.md`
  - `AgentRefactor/ComponentSpec.md`
  - `AgentRefactor/ImplementationPlan.md`
  - `AgentRefactor/provider-behavior-matrix.md`
  - `AgentRefactor/readme-feature-matrix.md`
  - `AgentRefactor/results-phase0.md`
- Added the neutral model-turn request/response contract:
  - `ModelRequest`
  - `ModelMessage`
  - `ModelAttachment`
  - `ModelResponse`
  - `ModelToolCall`
  - `ModelTurnCompletion`
  - `ModelPrewarmRequest`
  - `FeedbackAttachmentRequest`
- Added provider-neutral tool and output request types:
  - `ToolChoice`
  - top-level `ToolDefinition`
  - `ToolDefinitionKind`
  - `StructuredOutputRequest`
  - `ResponseFormat`
- Added the richer stream event taxonomy for future shared reduction:
  - `ModelStreamEvent`
  - `ToolInputStart`
  - `ToolCallPartial`
  - `ModelSource`
  - `ModelFile`
  - `ModelWarning` alias to the existing warning type
- Extended `LanguageModel` with the new neutral one-turn API:
  - `respond(to: ModelRequest) async throws -> ModelResponse`
  - `streamResponse(to: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error>`
  - `prewarm(for: ModelPrewarmRequest)`
  - `logFeedbackAttachment(_:)`
- Kept the current session-shaped provider methods in place with compatibility defaults so Phase 1 does not require migrating real providers yet.
- Added `LanguageModelContractError` for migration-time default failures.
- Added `Codable` conformance where needed by the model-turn codable tests:
  - `Instructions`
  - `TokenUsage`
  - `LanguageModelWarning`
  - `RateLimitState`
  - `ResponseMetadata`
  - `FinishReason`
  - `LanguageModelStreamError`
- Added focused Swift Testing coverage in `Tests/SwiftAgentTests/Core/ModelTurnContractTests.swift` for:
  - `ModelRequest` codable round trip.
  - `ModelResponse` codable round trip.
  - rich `ModelStreamEvent` equality/lifecycle coverage.
  - a minimal mock provider using the neutral `LanguageModel` turn API.

## Verification

Commands run:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -only-testing:SwiftAgentTests/ModelTurnContractTests -derivedDataPath .tmp/DerivedData-phase1-contract-final test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -derivedDataPath .tmp/DerivedData-phase1-tests-final test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" -derivedDataPath .tmp/DerivedData-phase1-example-final build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" -derivedDataPath .tmp/DerivedData-phase1-recorder-final build -quiet
swiftformat --config ".swiftformat" Sources/SwiftAgent/Core/Instructions.swift Sources/SwiftAgent/LanguageModel/LanguageModel.swift Sources/SwiftAgent/LanguageModel/LanguageModelStreamEvent.swift Sources/SwiftAgent/LanguageModel/ModelStreamEvent.swift Sources/SwiftAgent/LanguageModel/ModelTurnTypes.swift Sources/SwiftAgent/Models/TokenUsage.swift Tests/SwiftAgentTests/Core/ModelTurnContractTests.swift
git diff --check
```

Result:

- `ModelTurnContractTests`: passed.
- `SwiftAgentTests`: passed.
- `ExampleApp` iOS simulator build: passed.
- `AgentRecorder` macOS build: passed.
- `git diff --check`: passed.

Formatter note:

- Attempted `swiftformat --config ".swiftformat" ...` for changed Swift files, but `swiftformat` was not installed or available on `PATH` in this workspace (`zsh: command not found: swiftformat`).
- Also checked `/opt/homebrew/bin` and `/usr/local/bin`; no `swiftformat` binary was found.

## Notes For Phase 2

- Fork update: `ProviderContinuation` was removed after this phase. Public `LanguageModel` remains the provider/model backend API, and provider-native state is preserved through `providerMetadata` on model/transcript values.
- The old `LanguageModelSession`-shaped provider methods still exist and remain the path used by current providers and `LanguageModelSession`. They are isolated as compatibility surface for later phases rather than removed in Phase 1.
- `LanguageModelStreamEvent` remains in place for existing session streaming. `ModelStreamEvent` is the new provider-neutral event type that Phase 2's reducer should target.
- `ModelRequest.messages`, `ModelAttachment`, and `StructuredOutputRequest.includeSchemaInPrompt` are intentionally provider-neutral and do not define provider-specific serialization policy. Phase 2's `ModelRequestBuilder` decides how transcript prompt entries, schema prompt injection, groundings, image segments, and provider metadata become these values.
- The neutral `ToolDefinition` and completed `ModelToolCall` distinguish `.local` from `.providerDefined`, but execution policy still lives in the existing session/provider paths until `AgentSession` and the tool execution engine are built.

## 2026-04-29 Verification Update

- Phase 1 remains complete.
- Current source no longer contains `ProviderContinuation`.
- Current `ModelRequest`, `ModelResponse`, and `ModelStreamEvent` match the forked metadata-based design.
