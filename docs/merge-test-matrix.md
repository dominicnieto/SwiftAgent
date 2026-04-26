# Merge Test Matrix

## Purpose

Define the test coverage needed while merging AnyLanguageModel into SwiftAgent. This matrix separates always-run unit/replay tests from optional live-provider and local-runtime tests.

## Test Categories

### Always-Run Tests

These should run without API keys, local models, or network access.

- SwiftAgent core unit tests.
- SwiftAgent macro tests.
- Moved AnyLanguageModel core tests.
- Moved AnyLanguageModel macro tests.
- Transcript model tests.
- Generation schema/content conversion tests.
- Tool execution policy tests.
- GenerationOptions custom option tests.
- Provider capability model tests.
- Streaming event reducer tests.
- Replay fixture tests using recorded HTTP.
- AgentRecorder fixture formatting tests where possible.

### Replay Tests

Replay tests use recorded provider HTTP fixtures and should not hit live provider APIs.

Required replay coverage:

- OpenAI text response.
- OpenAI structured output.
- OpenAI tool calls.
- OpenAI streaming text.
- OpenAI streaming structured output.
- OpenAI streaming tool calls.
- OpenAI streaming reasoning where fixture data is available.
- Anthropic text response.
- Anthropic structured output.
- Anthropic streaming text.
- Anthropic streaming thinking.
- Anthropic streaming tool calls.
- Provider metadata/rate-limit parsing when fixture headers include it.

### Optional Live Tests

Live tests require credentials, local runtimes, or network access. They should be opt-in.

- OpenAI live scenarios.
- Anthropic live scenarios.
- Gemini live scenarios.
- Ollama local server scenarios.
- MLX local model scenarios.
- Llama local/server scenarios.
- SystemLanguageModel / Apple Foundation Models scenarios on supported OS versions.

## Current SwiftAgent Test Coverage To Preserve

Current SwiftAgent tests should be inventoried in Phase 0 and marked as:

- preserved unchanged
- adapted to merged API
- intentionally replaced
- removed because the behavior no longer exists

Important current behavior to preserve:

- `@SessionSchema` macro expansion.
- prompt building.
- transcript resolving.
- structured output decoding.
- tool decoding and execution.
- OpenAI request/response mapping.
- OpenAI streaming transcript updates.
- Anthropic request/response mapping.
- Anthropic streaming transcript updates.
- HTTP replay recording and replay client behavior.
- token usage accumulation.
- reasoning entries where providers expose reasoning.

## AnyLanguageModel Tests To Move

Copy the whole AnyLanguageModel repo first, including tests. After it builds in place, classify ALM tests as:

- core tests that should pass before merge changes
- provider tests that can become replay tests
- provider tests requiring live credentials
- local runtime tests requiring optional dependencies
- tests that need adaptation to the merged transcript/session API

Likely ALM test groups:

- `GeneratedContent`
- `GenerationSchema`
- `DynamicGenerationSchema`
- `Generable` macros
- `Prompt`
- `Instructions`
- `Transcript`
- `ToolExecutionDelegate`
- provider tests for OpenAI, OpenResponses, Anthropic, Gemini, Ollama, MLX, Llama, CoreML, SystemLanguageModel

## New Merge Tests

### Core Model Stack

- `Generable`, `GeneratedContent`, and `GenerationSchema` compile and behave through SwiftAgent imports.
- `Tool` arguments and output conversion work through the merged protocols.
- `GenerationOptions` common options encode/decode correctly.
- `GenerationOptions` typed custom options round-trip where possible.

### Transcript

- transcript supports instructions, prompts, reasoning, tool calls, tool outputs, responses, text segments, structured segments, and image segments.
- transcript upsert preserves order and updates by stable ID.
- transcript schema version is encoded.
- `firstDiff(comparedTo:)` identifies focused differences.
- structured output source is preserved.

### Streaming

- rich provider stream events reduce into transcript updates.
- snapshots derive from transcript/token state.
- final snapshot represents completed transcript state.
- tool call argument deltas are visible before tool execution.
- tool outputs are visible before final model response.
- reasoning entries remain separate from assistant text.
- token usage stays outside transcript entries.

### Capabilities

- provider capabilities use `OptionSet` checks.
- protocol inference sets expected flags.
- explicit capability reporting overrides inference when needed.
- unsupported requested features fail early or warn according to policy.

### Tool Execution Policy

- parallel tool execution can be enabled/disabled.
- missing tool policy works.
- retry policy works for retryable failures.
- failure policy emits tool output or throws according to configuration.
- approval hook can stop or modify tool execution.

### Provider Metadata and Logging

- provider request IDs are captured where available.
- rate-limit headers parse where available.
- retry-after hints parse where available.
- warnings appear in response/snapshot metadata.
- logging redacts credentials and sensitive values.

## Build Matrix

Always build:

- SwiftAgent SDK.
- SwiftAgent tests.
- SwiftAgent macro tests.
- AgentRecorder.

Optional builds:

- MLX provider product.
- Llama provider product.
- CoreML/SystemLanguageModel on supported Apple OS versions.
- Any provider product gated by optional dependencies.

## Exit Criteria

- Always-run tests pass without network or credentials.
- Replay tests cover OpenAI and Anthropic parity before SDK adapters are removed.
- AgentRecorder can generate updated fixtures using the merged provider/session API.
- Optional provider tests are documented and skipped clearly when dependencies are unavailable.

