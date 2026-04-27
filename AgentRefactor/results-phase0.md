# Phase 0 Results

Completed on 2026-04-26.

## Completed

- Read `AgentRefactor/Architecture.md`, `AgentRefactor/ComponentSpec.md`, and `AgentRefactor/ImplementationPlan.md`.
- Inventoried every current provider/API variant:
  - `OpenAILanguageModel(apiVariant: .chatCompletions)`
  - `OpenAILanguageModel(apiVariant: .responses)`
  - `OpenResponsesLanguageModel`
  - `AnthropicLanguageModel`
  - `SimulationLanguageModel` from `SimulatedSession`
- Added `AgentRefactor/provider-behavior-matrix.md` with current behavior, continuation requirements, metadata/usage support, and provider responsibility issues.
- Added `AgentRefactor/readme-feature-matrix.md` with README examples/features marked as `LanguageModelSession`, `AgentSession`, or shared.
- Inventoried the tests that must survive the refactor and captured baseline test commands/results below.

## Baseline Test Capture

Commands run:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests -derivedDataPath .tmp/DerivedData-phase0-main test -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentMacroTests -testPlan SwiftAgentMacroTests -derivedDataPath .tmp/DerivedData-phase0-macro test -quiet
```

Result:

- `SwiftAgentTests`: passed, command exited 0.
- `SwiftAgentMacroTests`: passed, command exited 0.
- Note: an earlier concurrent run without separate `-derivedDataPath` caused `SwiftAgentMacroTests` to fail with Xcode's build database locked. That was an execution artifact, not a product test failure, and was rerun with separate DerivedData paths.

## Build Verification

Commands run:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" -derivedDataPath .tmp/DerivedData-phase0-example build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" -derivedDataPath .tmp/DerivedData-phase0-recorder build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" -derivedDataPath .tmp/DerivedData-phase0-recorder-nosign CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" -derivedDataPath .tmp/DerivedData-phase0-recorder-signed build -quiet
```

Result:

- `ExampleApp`: passed, command exited 0.
- `AgentRecorder`: failed at codesigning. Xcode reported no matching "Mac Development" signing certificate for team ID `7F6BJZY5B3`. No compile error was reported before the signing failure.
- `AgentRecorder` with `CODE_SIGNING_ALLOWED=NO`: passed, command exited 0.
- `AgentRecorder` after signing update: passed, command exited 0.

## Tests That Must Survive

| Area | Current coverage | Refactor requirement |
| --- | --- | --- |
| Provider replay: OpenAI | `Tests/SwiftAgentTests/Providers/OpenAIProviderReplayTests.swift` | Preserve Chat Completions text, schema/image request serialization, Responses text streaming, structured streaming, streaming tool-call continuation, reasoning separation, metadata headers, refusal, HTTP errors, stream failure, malformed tool arguments. |
| Provider replay: Open Responses | `Tests/SwiftAgentTests/Providers/OpenResponsesProviderReplayTests.swift` | Preserve custom base URL/configuration, text, custom body/options/images, text streaming, structured streaming, streaming tool calls through policy, non-streaming tool execution, metadata, HTTP errors, stream failure, malformed tool arguments. |
| Provider replay: Anthropic | `Tests/SwiftAgentTests/Providers/AnthropicProviderReplayTests.swift` | Preserve configuration, text, options/schema/images, text streaming, structured streaming, streaming tool calls plus thinking and usage, non-streaming tool execution, metadata, HTTP errors, malformed tool arguments. |
| Provider capability tests | `Tests/SwiftAgentTests/Providers/LanguageModelCapabilitiesTests.swift` | Preserve normalized capability flags, image segment round trip, and partial structured generation behavior. |
| Session streaming | `Tests/SwiftAgentTests/Core/LanguageModelSessionStreamingTests.swift`, streaming tests in `GenerationOptionsTests.swift`, provider streaming replay tests | Preserve snapshot coalescing, transcript-derived snapshots, final transcript response recording, usage/metadata accumulation, and partial structured decoding. |
| Session observation | `Tests/SwiftAgentTests/Core/LanguageModelSessionObservationTests.swift` | Preserve `@Observable` notifications for transcript and `isResponding` during direct response and streaming. Add equivalent durable-state observation tests for `AgentSession`. |
| Tool execution policy | `Tests/SwiftAgentTests/Core/ToolExecutionPolicyTests.swift` | Move behavior from `LanguageModelSession` to `AgentSession`/tool engine without losing retries, missing-tool behavior, failure behavior, delegate stop/provide-output decisions, cancellation handling, and serial/parallel execution. |
| Transcript resolver and groundings | `Tests/SwiftAgentTests/Core/LanguageModelSessionGroundingTests.swift`, `Sources/ExampleCode/ReadmeCode.swift` compile coverage | Preserve typed groundings and `schema.resolve(transcript)` behavior for direct sessions and later agent sessions. |
| Transcript model | `Tests/SwiftAgentTests/Transcript/TranscriptCodableTests.swift` | Preserve codable/equatable transcript entries, generated content fields, image segments, reasoning entries, tool calls, and tool outputs. |
| Macro tests | `Tests/SwiftAgentMacroTests/SessionSchemaMacroTests.swift`, `SessionSchemaMacroEdgeShapesTests.swift` | Preserve `@SessionSchema` expansions, default/injected tools, structured-output-only schemas, no-tool schemas, and declaration order. |
| Prompt/instructions/core types | `PromptBuilderTests`, `PromptTests`, `InstructionsTests`, `GenerationGuideTests`, `DynamicGenerationSchemaTests`, `GenerationOptionsTests`, `JSONValueTests`, `ConvertibleToGeneratedContentTests`, `AvailabilityTests` | Keep shared request/schema primitives stable while introducing neutral model-turn types. |
| Simulation provider | `Tests/SwiftAgentTests/Providers/Simulation/*` | Preserve deterministic default generation consumption, text response, streaming response, token usage, reasoning entries, and mock tool-run transcript entries. |
| Replay recorder | `Tests/SwiftAgentTests/Replay/HTTPReplayRecorderTests.swift` | Preserve SSE encoding and paste-ready fixture output used by AgentRecorder/provider replay workflows. |
| Tool/schema protocols | `Tests/SwiftAgentTests/Protocols/*` | Preserve tool JSON schema encoding and `@Generable` defaulted-property decoding. |

Gap found:

- `ToolRunRejection` is documented and implemented, but Phase 0 did not find a dedicated test named around recoverable rejection behavior. Add or preserve coverage when tool execution moves into `AgentSession`.

## Key Findings

- The current provider protocol is session-shaped: providers receive `LanguageModelSession` and read `session.transcript`, `session.tools`, and session tool policy directly.
- OpenAI, Open Responses, and Anthropic providers currently own automatic tool loops. This is the main behavior that must move to `AgentSession`.
- Responses-style providers already expose the need for opaque continuation. They preserve raw `reasoning` and `function_call` output items and append `function_call_output` items on continuation.
- Anthropic also needs provider-native continuation even though it does not currently advertise `.responseContinuation`. Tool continuation depends on assistant `tool_use` content blocks and user `tool_result` content blocks; thinking signatures need to remain provider-native.
- `OpenAILanguageModel` capability reporting is API-variant-sensitive. Chat Completions does not advertise streaming tool calls; Responses does.
- Structured streaming works in current Responses stream paths through partial JSON decoding, but capability flags only advertise `.structuredStreaming` for Anthropic.
- `SimulationLanguageModel` is best treated as a deterministic provider for tests/previews, not as an agent loop. It can emit reasoning/tool transcript entries from configured generations but does not exercise provider-native continuation.

## Risks And Notes

- Phase 1 should not design `ProviderContinuation` around public transcript entries. Public transcript lacks enough provider-native state for Responses reasoning/function calls and Anthropic thinking/tool-use signatures.
- Moving tool execution out of providers will require replay test rewrites. The preserved assertions should move from "provider executes tools through main session policy" to "provider emits tool calls; `AgentSession` executes tools and sends provider continuation."
- `LanguageModelSession` may still need an API for tool definitions/manual tool-call inspection, but it must not continue to own tool execution policy or delegates.
- Agent streaming needs to preserve richer provider events than current response snapshots: text deltas, structured deltas, reasoning, partial tool inputs, completed calls, tool outputs, usage, metadata, finish, raw events, and errors.
- Token usage aggregation currently happens through session state across provider-owned loops. After the refactor, aggregation should live in `ConversationEngine`/`AgentSession`.
- Current README wording repeatedly calls direct session streaming an agent flow. Phase 8 should make direct conversation and agent execution distinct concepts.

## Concrete Notes For Phase 1

- Define `ModelRequest` so it carries:
  - public messages/prompt/instructions,
  - tool definitions,
  - response format,
  - generation options,
  - attachments/images,
  - optional `ProviderContinuation`.
- Define `ModelResponse` so providers can return final content, transcript entries, tool calls, reasoning, finish reason, usage, metadata, raw provider output, and next continuation without executing tools.
- Define stream events before migrating providers. The current `LanguageModelStreamEvent` is close, but Phase 1 should add explicit completion/continuation semantics and avoid session-specific naming.
- Keep `ProviderContinuation` package/internal initially. Include provider name, model ID, turn ID, and opaque `JSONValue` payload.
- Add mock-provider tests for text, structured output, streaming deltas, tool-call completion, and opaque continuation before migrating real providers.
- Treat current provider capability flags as data to preserve, not as the only source of truth. Some current flags are incomplete or variant-sensitive.
- Keep Phase 1 provider migration minimal. The plan's "new protocol compiles with a mock provider" exit criterion is the right boundary.
