# Phase 0 Inventory

## Scope

Inventory for the planned no-bridge merge of `/Users/dominicnieto/Desktop/AnyLanguageModel` into SwiftAgent. This phase records current surfaces and overlap only. It does not choose canonical Phase 2 types.

## SwiftAgent Inventory

### Package and Targets

- `Package.swift`
  - Products: `OpenAISession`, `AnthropicSession`, `ExampleCode`.
  - Targets: `SwiftAgent`, `SwiftAgentMacros`, `OpenAISession`, `AnthropicSession`, `SimulatedSession`, `ExampleCode`, `SwiftAgentTests`, `SwiftAgentMacroTests`.
  - Platforms: iOS 26, macOS 26.
  - Dependencies: `swift-syntax`, MacPaw `OpenAI`, `SwiftAnthropic`, `EventSource`, `swift-macro-testing`.

### Public API Shape

- Core agent target: `Sources/SwiftAgent`
  - Agent/session state: `AgentResponse`, `AgentSnapshot`, `TokenUsage`, `Transcript`, `Transcript+Resolved`, `ToolRun`, `ToolRunRejection`, `StructuredOutputSnapshot`.
  - Provider/session abstraction: `LanguageModelProvider`, `Adapter`, `AdapterUpdate`, `AdapterGenerationOptions`, `AdapterModel`, `AdapterConfiguration`.
  - Schema/tool protocols: `LanguageModelSessionSchema`, `StructuredOutput`, `DecodableStructuredOutput`, `SwiftAgentTool`, `DecodableTool`.
  - Prompting: `Prompt`, `PromptBuilder`, `PromptRepresentable`, `PromptSection`, `PromptTag`, prompt builtins.
  - Networking/logging/replay: `HTTPClient`, `URLSessionHTTPClient`, `HTTPReplayRecorder`, `HTTPClientInterceptors`, `NetworkLog`, `AgentLog`.
  - Macro surface: `@SessionSchema` in `Sources/SwiftAgent/Macros.swift`.
- Provider products:
  - `Sources/OpenAISession`: `OpenAISession`, `OpenAIAdapter`, `OpenAIModel`, `OpenAIConfiguration`, `OpenAIGenerationOptions`.
  - `Sources/AnthropicSession`: `AnthropicSession`, `AnthropicAdapter`, `AnthropicModel`, `AnthropicConfiguration`, `AnthropicGenerationOptions`.
  - `Sources/SimulatedSession`: `SimulatedSession`, `SimulationAdapter`, `SimulationModel`, `SimulationConfiguration`, `SimulationGenerationOptions`, `SimulatedGeneration`, `MockableTool`.

### Transcript and Streaming Behavior To Preserve

- `Sources/SwiftAgent/Models/Transcript.swift` is agent-grade and codable/equatable.
  - Entries: `prompt`, `reasoning`, `toolCalls`, `toolOutput`, `response`.
  - Segments: `text`, `structure`.
  - Keeps provider correlation details: `ToolCall.callId`, `ToolOutput.callId`, tool names, status.
  - Keeps reasoning separate from response text with `summary`, `encryptedReasoning`, `status`.
  - Supports `upsert` by stable entry ID for streaming updates.
- `Sources/SwiftAgent/Models/AdapterUpdate.swift` streams `transcript(Transcript.Entry)` and `tokenUsage(TokenUsage)` separately.
- `LanguageModelProvider+StreamResponse.swift` derives public `AgentSnapshot` values from transcript state and token usage, with minimum snapshot interval options.
- `AgentResponse` and `AgentSnapshot` expose generated content, transcript, and token usage.

### FoundationModels and Provider SDK Usage

- Current SwiftAgent side has broad Apple `FoundationModels` usage: 138 matches across `Sources`, `Tests`, `AgentRecorder`, and `Examples`.
  - Core wrappers/protocols use `FoundationModels.Tool`, `Generable`, `GeneratedContent`, and `GenerationSchema`.
  - `SwiftAgentMacros` emits `FoundationModels.Tool` constraints.
  - Provider sessions accept variadic `FoundationModels.Tool` values and wrap them in `_SwiftAgentToolWrapper`.
- OpenAI SDK usage: 74 matches.
  - `Package.swift` depends on MacPaw `OpenAI`.
  - `OpenAIAdapter` maps Responses API requests, streaming events, schemas, tool calls, error mapping, and usage.
  - Tests use `CreateModelResponseQuery` and inline replay JSON/SSE fixtures.
- SwiftAnthropic usage: 77 matches.
  - `Package.swift` depends on `SwiftAnthropic`.
  - `AnthropicAdapter` maps Messages API requests, streaming events, schemas, tool calls, thinking, errors, and usage.
  - Tests use `MessageParameter`, `Model`, and inline replay JSON/SSE fixtures.

### AgentRecorder

- Location: `AgentRecorder/AgentRecorder`.
- CLI concerns:
  - Options/secrets: `CLI/AgentRecorderOptions.swift`, `CLI/AgentRecorderSecrets.swift`.
  - Secrets from `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `AGENT_RECORDER_SECRETS_PLIST`, or `Secrets.plist`.
  - Output supports request inclusion, header inclusion, and JSON pretty printing.
- Current scenarios: `Scenarios/ScenarioCatalog.swift`
  - Anthropic: text, streaming text, streaming thinking, structured output, streaming weather tool call, streaming no-args ping tool call.
  - OpenAI: text, streaming text, streaming structured output, structured output, non-streaming weather tool call, streaming multiple tool calls, streaming weather tool call.
- Current coupling:
  - Imports `OpenAISession`, `AnthropicSession`, `FoundationModels`, MacPaw `OpenAI`, and `SwiftAnthropic`.
  - Recording transport is injected through `OpenAIConfiguration.recording` and `AnthropicConfiguration.recording`, backed by `HTTPReplayRecorder` and `URLSessionHTTPClient`.

## AnyLanguageModel Inventory

### Package and Targets

- `/Users/dominicnieto/Desktop/AnyLanguageModel/Package.swift`
  - Product: `AnyLanguageModel`.
  - Targets: `AnyLanguageModel`, `AnyLanguageModelMacros`, `AnyLanguageModelTests`.
  - Platforms: macOS 14, Mac Catalyst 17, iOS 17, tvOS 17, watchOS 10, visionOS 1.
  - Traits: `CoreML`, `MLX`, `Llama`, `AsyncHTTPClient`.
  - Dependencies: `swift-transformers`, `EventSource`, `JSONSchema`, `llama.swift`, `PartialJSONDecoder`, `mlx-swift-lm`, `swift-syntax`, `async-http-client`.

### Public API Shape

- FoundationModels-style core:
  - `Availability`, `Generable`, `GeneratedContent`, `GenerationSchema`, `DynamicGenerationSchema`, `GenerationGuide`, `GenerationID`.
  - `Prompt`, `PromptBuilder`, `PromptRepresentable`.
  - `Instructions`, `InstructionsBuilder`, `InstructionsRepresentable`.
  - `Tool`, `ToolExecutionDelegate`, `ToolExecutionDecision`.
  - `LanguageModel`, `LanguageModelSession`, `LanguageModelFeedback`.
  - `GenerationOptions` with `sampling`, `temperature`, `maximumResponseTokens`, and typed model custom options via `options[custom: Model.self]`.
  - Macros: `@Generable`, `@Guide`.
- Direct providers:
  - `OpenAILanguageModel`, `OpenResponsesLanguageModel`, `AnthropicLanguageModel`, `GeminiLanguageModel`, `OllamaLanguageModel`.
  - Optional/local/platform providers: `SystemLanguageModel`, `CoreMLLanguageModel`, `MLXLanguageModel`, `LlamaLanguageModel`.
- Transport:
  - `Shared/Transport.swift` typealiases `HTTPSession` to `AsyncHTTPClient.HTTPClient` when available, otherwise `URLSession`.
  - `Extensions/URLSession+Extensions.swift` and `Extensions/HTTPClient+Extensions.swift` implement request/stream helpers.

### Transcript and Streaming Shape

- `/Users/dominicnieto/Desktop/AnyLanguageModel/Sources/AnyLanguageModel/Transcript.swift`
  - Entries: `instructions`, `prompt`, `toolCalls`, `toolOutput`, `response`.
  - Segments: `text`, `structure`, `image`.
  - Instructions include tool definitions.
  - Prompt entries include segments, `GenerationOptions`, and `ResponseFormat`.
  - Tool calls lack SwiftAgent's explicit provider `callId` and status fields.
  - No reasoning entry.
- `LanguageModelSession.Response<Content>` exposes `content`, `rawContent`, and `transcriptEntries`.
- `LanguageModelSession.ResponseStream<Content>.Snapshot` exposes `content` and `rawContent`, but not transcript or token usage.
- Several providers stream content snapshots from accumulated text/JSON, not transcript-first events.

### Provider Coverage and Gating

- OpenAI:
  - `OpenAILanguageModel` supports Chat Completions and Responses API variants.
  - `OpenResponsesLanguageModel` separately supports OpenResponses-compatible endpoints.
  - Live tests require `OPENAI_API_KEY` or `OPEN_RESPONSES_API_KEY` plus `OPEN_RESPONSES_BASE_URL`.
- Anthropic:
  - `AnthropicLanguageModel` includes custom generation options for metadata, stop sequences, tool choice, thinking, service tier, and extra body.
  - Live tests require `ANTHROPIC_API_KEY`.
- Gemini:
  - Live tests require `GEMINI_API_KEY`.
- Ollama:
  - Tests are enabled outside CI and assume a local server/runtime.
- SystemLanguageModel:
  - Wrapped around Apple `FoundationModels.SystemLanguageModel`; tests are availability-gated.
- CoreML, MLX, Llama:
  - Trait-gated and/or environment-gated with `ENABLE_COREML_TESTS`, `ENABLE_MLX_TESTS`, `HF_TOKEN`, and `LLAMA_MODEL_PATH`.

### FoundationModels Usage

- AnyLanguageModel mostly replaces FoundationModels primitives locally.
- Apple `FoundationModels` usage is concentrated in `Models/SystemLanguageModel.swift` and FoundationModels compatibility/conversion tests.
- Current count: 103 matches under AnyLanguageModel `Sources` and `Tests`, primarily conversion into/from Apple `SystemLanguageModel`, `LanguageModelSession`, `GenerationSchema`, `GeneratedContent`, `Prompt`, `Instructions`, `Tool`, and `Transcript`.

## Duplicate Concepts For Phase 2 Decision

Do not decide these in Phase 0.

- Session engine:
  - SwiftAgent: `LanguageModelProvider` plus provider-specific `OpenAISession`/`AnthropicSession`.
  - AnyLanguageModel: canonical-looking `LanguageModelSession(model:tools:instructions:)`.
- Provider boundary:
  - SwiftAgent: `Adapter`, `AdapterUpdate`, `AdapterModel`, `AdapterGenerationOptions`, provider SDK adapters.
  - AnyLanguageModel: `LanguageModel` providers with direct HTTP/local implementations.
- Transcript:
  - SwiftAgent has reasoning, call IDs, status, transcript upsert, resolved transcript APIs.
  - AnyLanguageModel has instructions, image segments, prompt options/response format, tool definitions.
- Streaming snapshot/update model:
  - SwiftAgent streams transcript/token updates and derives `AgentSnapshot`.
  - AnyLanguageModel streams `content`/`rawContent` snapshots.
- Generation options:
  - SwiftAgent has provider-specific `OpenAIGenerationOptions`, `AnthropicGenerationOptions`, `SimulationGenerationOptions`.
  - AnyLanguageModel has one `GenerationOptions` with model-specific custom options.
- Tool protocols:
  - SwiftAgent wraps `FoundationModels.Tool` as `SwiftAgentTool` and adds `DecodableTool`.
  - AnyLanguageModel defines its own `Tool<Arguments, Output>`, schema injection, and `ToolExecutionDelegate`.
- Generated content/schema/generability:
  - SwiftAgent currently imports Apple `GeneratedContent`, `GenerationSchema`, `Generable`.
  - AnyLanguageModel defines local `GeneratedContent`, `GenerationSchema`, `DynamicGenerationSchema`, `Generable`, macros, and conversion protocols.
- Prompt/instructions:
  - SwiftAgent has a richer prompt builder with source metadata for transcript resolving.
  - AnyLanguageModel has FoundationModels-style `Prompt` and `Instructions` builders.
- Model identifiers:
  - SwiftAgent has `OpenAIModel`, `AnthropicModel`, and `SimulationModel`.
  - AnyLanguageModel direct providers generally use string model IDs plus provider custom options.
- Transport/replay/logging:
  - SwiftAgent has `HTTPClient`, `HTTPReplayRecorder`, `NetworkLog`, `AgentLog`.
  - AnyLanguageModel has `HTTPSession` abstraction over URLSession/AsyncHTTPClient and direct provider request helpers.
- Structured output and macros:
  - SwiftAgent has `@SessionSchema`, `StructuredOutput`, `DecodableStructuredOutput`, transcript resolver.
  - AnyLanguageModel has `@Generable`, `@Guide`, `StructuredGeneration`, `PartialJSONDecoder`.

## Tests and Fixtures

### SwiftAgent Tests To Preserve Or Adapt

- Preserve behavior, adapt API as needed:
  - Macro expansion: `Tests/SwiftAgentMacroTests/SessionSchemaMacroTests.swift`, `SessionSchemaMacroEdgeShapesTests.swift`.
  - Prompt building: `Tests/SwiftAgentTests/PromptBuilderTests.swift`.
  - Transcript codable/stable JSON behavior: `Tests/SwiftAgentTests/TranscriptCodableTests.swift`, `GeneratedContent+StableJSON.swift` expectations.
  - Tool JSON schema: `Tests/SwiftAgentTests/Protocols/DecodableToolJSONSchemaTests.swift`.
  - Simulation behavior: `Tests/SwiftAgentTests/SimulatedSession/*`.
  - Replay recorder formatting and SSE encoding: `Tests/SwiftAgentTests/Networking/HTTPReplayRecorderTests.swift`.
- Provider replay tests must be preserved semantically, then adapted or regenerated:
  - OpenAI text, structured output, non-streaming tool calls, streaming text, streaming structured output, streaming tool calls, multiple tool calls, malformed tool arguments, streaming/provider error handling, generation option validation.
  - Anthropic text, structured output, streaming text, streaming thinking, streaming tool calls, multiple/no-args tool calls, HTTP error mapping, thinking option validation.
- Current fixtures are inline raw string JSON/SSE constants in test files, consumed by `Tests/SwiftAgentTests/Helpers/ReplayHTTPClient.swift`; there is no separate checked-in fixture directory found in Phase 0.

### AgentRecorder Tests/Scenarios To Preserve Or Adapt

- Preserve CLI workflow and scenario IDs where possible.
- Adapt scenario implementations from `OpenAISession`/`AnthropicSession` to `LanguageModelSession` plus direct provider models.
- Preserve `HTTPReplayRecorder` request/response/SSE capture, paste-ready Swift fixture snippets, auth-header omission by default, and scenario-to-unit-test file mapping.

### AnyLanguageModel Tests To Move/Classify Later

- Core always-run candidates:
  - `GeneratedContent`, `ConvertibleToGeneratedContent`, `GenerationSchema`, `DynamicGenerationSchema`, `GenerationGuide`, `Prompt`, `Instructions`, `Transcript`, `ToolExecutionDelegate`, `CustomGenerationOptions`, `StructuredGeneration`, `GenerableMacro`, `MockLanguageModel`, `Locked`, JSON/URLSession helpers.
- Compatibility/adaptation candidates:
  - `APICompatibilityAnyLanguageModelTests.swift`, `APICompatibilityFoundationModelsTests.swift`, `DynamicSchemaConversionTests.swift`, `SystemLanguageModelTests.swift`.
- Provider tests requiring live credentials or local runtimes:
  - `OpenAILanguageModelTests.swift`, `OpenResponsesLanguageModelTests.swift`, `AnthropicLanguageModelTests.swift`, `GeminiLanguageModelTests.swift`, `OllamaLanguageModelTests.swift`, `CoreMLLanguageModelTests.swift`, `MLXLanguageModelTests.swift`, `LlamaLanguageModelTests.swift`.
- Provider tests are mostly live/runtime tests today, not replay tests. They should become replay-backed where they cover OpenAI/Anthropic parity needed to remove SDK adapters.

## Initial Source-Compatible APIs Worth Preserving

- `@SessionSchema` and resolved transcript ergonomics.
- `LanguageModelSession(model:tools:instructions:)` as the preferred canonical construction shape.
- `OpenAILanguageModel`, `OpenResponsesLanguageModel`, and `AnthropicLanguageModel` as distinct provider types.
- SwiftAgent `AgentResponse`/`AgentSnapshot` behavior: content plus transcript plus token usage.
- SwiftAgent transcript fidelity: reasoning entries, tool call/output correlation IDs, status, stable upsert.
- AnyLanguageModel core primitives: `Generable`, `GeneratedContent`, `GenerationSchema`, `DynamicGenerationSchema`, `Prompt`, `Instructions`, `Tool`, `GenerationOptions`.
- `HTTPReplayRecorder` and AgentRecorder scenario workflow.

## Test Coverage Checklist

- Preserve or adapt: `@SessionSchema` macro expansion in `Tests/SwiftAgentMacroTests/SessionSchemaMacroTests.swift` and `Tests/SwiftAgentMacroTests/SessionSchemaMacroEdgeShapesTests.swift`.
- Preserve or adapt: prompt rendering/source behavior in `Tests/SwiftAgentTests/PromptBuilderTests.swift`.
- Preserve or adapt: transcript codable and stable generated-content JSON behavior in `Tests/SwiftAgentTests/TranscriptCodableTests.swift`.
- Preserve or adapt: tool schema generation in `Tests/SwiftAgentTests/Protocols/DecodableToolJSONSchemaTests.swift`.
- Preserve or adapt: simulated text, streaming text, and multi-turn exhaustion in `Tests/SwiftAgentTests/SimulatedSession/*`.
- Preserve or adapt: HTTP replay recorder SSE encoding and paste-ready fixture snippet formatting in `Tests/SwiftAgentTests/Networking/HTTPReplayRecorderTests.swift`.
- Preserve or adapt with replay parity: OpenAI text, structured output, non-streaming tool calls, streaming text, streaming structured output, streaming tool calls, streaming multiple tool calls, malformed tool arguments, streaming errors, HTTP errors, and generation option validation in `Tests/SwiftAgentTests/OpenAISession/*`.
- Preserve or adapt with replay parity: Anthropic text, structured output, streaming text, streaming thinking, streaming tool calls, streaming multiple tool calls, streaming no-args tool calls, HTTP errors, thinking round-trip, and generation option validation in `Tests/SwiftAgentTests/AnthropicSession/*`.
- Move/classify: AnyLanguageModel core tests for generated content, schema, prompts, instructions, transcript, tool execution, custom options, structured generation, macros, mock model, locking, and helpers.
- Move/classify as compatibility tests: AnyLanguageModel API compatibility, FoundationModels compatibility, dynamic schema conversion, and SystemLanguageModel tests.
- Keep optional/live gated: AnyLanguageModel OpenAI, OpenResponses, Anthropic, Gemini, Ollama, CoreML, MLX, Llama provider tests until replay/local-runtime strategy is decided.
- Replace or regenerate intentionally: inline provider replay JSON/SSE constants in SwiftAgent provider tests when direct provider request/response formats change.

## Streaming Baseline Fixtures

- OpenAI streaming text: `Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingTextTests.swift` verifies partial content, final transcript count, prompt entry, reasoning entry, response entry, request shape, and inline SSE fixture `helloWorldResponse`.
- OpenAI streaming structured output: `Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingStructuredOutputTests.swift` verifies partial structured snapshots and final structured response transcript with inline SSE fixture `structuredOutputResponse`.
- OpenAI streaming tool calls: `Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingToolCallsTests.swift`, `OpenAIStreamingMultipleToolCallsTests.swift`, and `OpenAIStreamingMalformedToolArgumentsTests.swift` verify tool-call replay requests, reasoning, call IDs, tool output entries, malformed argument errors, and inline SSE fixtures.
- OpenAI streaming errors: `Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingErrorHandling.swift` verifies cancellation and provider error events.
- Anthropic streaming text: `Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingTextTests.swift` verifies streamed content, request shape, final transcript, token usage, and inline SSE fixture `streamingResponse`.
- Anthropic streaming thinking: `Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingThinkingRoundtripTests.swift` verifies thinking blocks/signatures can round-trip into follow-up requests with inline SSE fixtures.
- Anthropic streaming tool calls: `Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingToolCallsTests.swift`, `AnthropicStreamingMultipleToolCallsTests.swift`, and `AnthropicStreamingToolCallsNoArgsTests.swift` verify tool use, multiple tool calls, empty arguments, tool outputs, and replay request shape with inline SSE fixtures.
- Simulated streaming: `Tests/SwiftAgentTests/SimulatedSession/SimulationStreamingTextTests.swift` verifies provider-independent snapshot behavior.

## Import and SDK Inventory

### SwiftAgent FoundationModels Import Files

These files import Apple `FoundationModels` directly and must be addressed when local core primitives replace it:

```text
AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStreamingTextScenario.swift
AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStreamingThinkingScenario.swift
AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStreamingToolCallsNoArgsPingScenario.swift
AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStreamingToolCallsWeatherScenario.swift
AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStructuredOutputScenario.swift
AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicTextScenario.swift
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingStructuredOutputScenario.swift
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingTextScenario.swift
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingToolCallsMultipleScenario.swift
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingToolCallsWeatherScenario.swift
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStructuredOutputScenario.swift
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAITextScenario.swift
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIToolCallsWeatherScenario.swift
Examples/Example App/ExampleApp/Examples/CalculatorToolRunView.swift
Examples/Example App/ExampleApp/Examples/WeatherToolRunView.swift
Examples/Example App/ExampleApp/Session/OpenAISession.swift
Sources/AnthropicSession/AnthropicAdapter+Streaming.swift
Sources/AnthropicSession/AnthropicAdapter+StreamingHandlers.swift
Sources/AnthropicSession/AnthropicAdapter+StreamingTranscript.swift
Sources/AnthropicSession/AnthropicAdapter+ToolExecution.swift
Sources/AnthropicSession/AnthropicAdapter.swift
Sources/AnthropicSession/AnthropicModel.swift
Sources/AnthropicSession/AnthropicSession.swift
Sources/AnthropicSession/AnthropicStreamingState.swift
Sources/AnthropicSession/Helpers/AnthropicMessageBuilder.swift
Sources/AnthropicSession/Helpers/GenerationSchema+AnthropicJSONSchema.swift
Sources/ExampleCode/ReadmeCode.swift
Sources/OpenAISession/Helpers/GenerationSchema+JSONSchema.swift
Sources/OpenAISession/OpenAIAdapter+Streaming.swift
Sources/OpenAISession/OpenAIAdapter.swift
Sources/OpenAISession/OpenAIConfiguration.swift
Sources/OpenAISession/OpenAIModel.swift
Sources/OpenAISession/OpenAISession.swift
Sources/SimulatedSession/MockableTool.swift
Sources/SimulatedSession/SimulatedGeneration.swift
Sources/SimulatedSession/SimulatedSession.swift
Sources/SimulatedSession/SimulationAdapter.swift
Sources/SimulatedSession/SimulationConfiguration.swift
Sources/SimulatedSession/SimulationModel.swift
Sources/SwiftAgent/Helpers/GeneratedContent+StableJSON.swift
Sources/SwiftAgent/Helpers/RejectionReportDetailsExtractor.swift
Sources/SwiftAgent/Helpers/TranscriptResolver.swift
Sources/SwiftAgent/LanguageModelProvider/LanguageModelProvider+Respond.swift
Sources/SwiftAgent/LanguageModelProvider/LanguageModelProvider+StreamResponse.swift
Sources/SwiftAgent/LanguageModelProvider/LanguageModelProvider.swift
Sources/SwiftAgent/Models/AgentResponse.swift
Sources/SwiftAgent/Models/AgentSnapshot.swift
Sources/SwiftAgent/Models/StructuredOutputSnapshot.swift
Sources/SwiftAgent/Models/ToolRun.swift
Sources/SwiftAgent/Models/ToolRunRejection.swift
Sources/SwiftAgent/Models/Transcript+Resolved.swift
Sources/SwiftAgent/Models/Transcript.swift
Sources/SwiftAgent/Models/_SwiftAgentToolWrapper.swift
Sources/SwiftAgent/Protocols/Adapter.swift
Sources/SwiftAgent/Protocols/DecodableStructuredOutput.swift
Sources/SwiftAgent/Protocols/DecodableTool.swift
Sources/SwiftAgent/Protocols/LanguageModelSessionSchema.swift
Sources/SwiftAgent/Protocols/StructuredOutput.swift
Sources/SwiftAgent/Protocols/SwiftAgentTool.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicGenerationOptionsValidationTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicHTTPErrorMappingTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingMultipleToolCallsTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingTextTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingThinkingRoundtripTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingToolCallsNoArgsTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingToolCallsTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStructuredOutputTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicTextTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicThinkingCompatibilityValidationTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIErrorHandling.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIGenerationOptionsValidationTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingErrorHandling.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingMalformedToolArgumentsTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingMultipleToolCallsTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingStructuredOutputTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingTextTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingToolCallsTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStructuredOutputTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAITextTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIToolCallsTests.swift
Tests/SwiftAgentTests/Protocols/DecodableToolJSONSchemaTests.swift
Tests/SwiftAgentTests/SimulatedSession/SimulationMultiTurnExhaustionTests.swift
Tests/SwiftAgentTests/SimulatedSession/SimulationStreamingTextTests.swift
Tests/SwiftAgentTests/SimulatedSession/SimulationTextTests.swift
Tests/SwiftAgentTests/TranscriptCodableTests.swift
```

Additional SwiftAgent references without direct imports include generated macro expectation strings in `Tests/SwiftAgentMacroTests/*` and `FoundationModels.Tool` text emitted by `Sources/SwiftAgentMacros/SessionSchema/SessionSchemaMacro.swift`.

### SwiftAgent OpenAI SDK Import Files

```text
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingStructuredOutputScenario.swift
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingTextScenario.swift
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStreamingToolCallsWeatherScenario.swift
AgentRecorder/AgentRecorder/Scenarios/OpenAI/OpenAIStructuredOutputScenario.swift
Sources/OpenAISession/Helpers/GenerationError+OpenAI.swift
Sources/OpenAISession/Helpers/GenerationSchema+JSONSchema.swift
Sources/OpenAISession/Helpers/OpenAIResponseStreamEventDecoder.swift
Sources/OpenAISession/Helpers/OutputContent+asText.swift
Sources/OpenAISession/OpenAIAdapter+Streaming.swift
Sources/OpenAISession/OpenAIAdapter.swift
Sources/OpenAISession/OpenAIGenerationOptions.swift
Sources/OpenAISession/OpenAIModel.swift
Sources/SimulatedSession/SimulationModel.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIErrorHandling.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIGenerationOptionsValidationTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingErrorHandling.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingMalformedToolArgumentsTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingMultipleToolCallsTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingStructuredOutputTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingTextTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStreamingToolCallsTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIStructuredOutputTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAITextTests.swift
Tests/SwiftAgentTests/OpenAISession/OpenAIToolCallsTests.swift
```

### SwiftAgent SwiftAnthropic SDK Import Files

```text
AgentRecorder/AgentRecorder/Scenarios/Anthropic/AnthropicStreamingThinkingScenario.swift
Sources/AnthropicSession/AnthropicAdapter+Request.swift
Sources/AnthropicSession/AnthropicAdapter+Streaming.swift
Sources/AnthropicSession/AnthropicAdapter+StreamingHandlers.swift
Sources/AnthropicSession/AnthropicAdapter+TokenUsage.swift
Sources/AnthropicSession/AnthropicAdapter.swift
Sources/AnthropicSession/AnthropicGenerationOptions.swift
Sources/AnthropicSession/AnthropicModel.swift
Sources/AnthropicSession/Helpers/AnthropicMessageBuilder.swift
Sources/AnthropicSession/Helpers/AnthropicMessageStreamEventDecoder.swift
Sources/AnthropicSession/Helpers/GenerationSchema+AnthropicJSONSchema.swift
Sources/AnthropicSession/Helpers/MessageParameter+Sendable.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicGenerationOptionsValidationTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicHTTPErrorMappingTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingMultipleToolCallsTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingTextTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingThinkingRoundtripTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingToolCallsNoArgsTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStreamingToolCallsTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicStructuredOutputTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicTextTests.swift
Tests/SwiftAgentTests/AnthropicSession/AnthropicThinkingCompatibilityValidationTests.swift
```

### AnyLanguageModel FoundationModels Usage Files

AnyLanguageModel does not use direct `import FoundationModels` lines in the scanned files. It references Apple FoundationModels symbols in:

```text
/Users/dominicnieto/Desktop/AnyLanguageModel/Sources/AnyLanguageModel/Models/SystemLanguageModel.swift
/Users/dominicnieto/Desktop/AnyLanguageModel/Tests/AnyLanguageModelTests/DynamicSchemaConversionTests.swift
```

## Phase 0 Completion Audit

- Complete: `plans/phase-0-inventory-plan.md` exists.
- Complete: `docs/phase-0-inventory.md` exists.
- Complete: SwiftAgent public API shape is recorded under "SwiftAgent Inventory".
- Complete: AnyLanguageModel public API shape is recorded under "AnyLanguageModel Inventory".
- Complete: tests that must continue to pass or be rewritten are identified under "Tests and Fixtures" and "Test Coverage Checklist".
- Complete: `FoundationModels` imports/references are inventoried in prose and file lists.
- Complete: OpenAI and SwiftAnthropic SDK imports are inventoried in prose and file lists.
- Complete: duplicate concepts are listed under "Duplicate Concepts For Phase 2 Decision" without selecting canonical sources.
- Complete: current SwiftAgent streaming behavior is captured under "Transcript and Streaming Behavior To Preserve" and "Streaming Baseline Fixtures".
- Complete: AnyLanguageModel provider coverage and gating are captured under "Provider Coverage and Gating".
- Complete: outputs include this inventory doc, the explicit test coverage checklist, and the initial source-compatible API list.

## Phase 0 Follow-Ups

- Phase 1 should copy AnyLanguageModel mechanically before pruning or relocating.
- Phase 2 needs an approval table for every duplicate concept above before implementation.
- Provider replacement phases need replay parity before removing MacPaw `OpenAI` or `SwiftAnthropic`.
- Streaming provider gaps should be treated as blockers: AnyLanguageModel providers that emit content-only snapshots need transcript-first update coverage before they replace SwiftAgent adapters.
