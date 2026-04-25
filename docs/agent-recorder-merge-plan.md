# AgentRecorder Merge Plan

## Purpose

AgentRecorder is the SwiftAgent CLI used to record real provider HTTP traffic and print paste-ready Swift fixtures for replay tests.

The merge must preserve this workflow because replay fixtures are central to verifying provider behavior without live API calls.

## Current Role

AgentRecorder currently:

- runs provider scenarios against live OpenAI and Anthropic APIs
- records HTTP requests/responses through `HTTPReplayRecorder`
- supports streaming server-sent-event responses
- prints Swift fixture snippets
- maps scenarios to existing unit test files
- supports secrets from environment variables or a local plist

Current scenario coverage includes:

- OpenAI text
- OpenAI structured output
- OpenAI tool calls
- OpenAI streaming text
- OpenAI streaming structured output
- OpenAI streaming tool calls
- Anthropic text
- Anthropic structured output
- Anthropic streaming text
- Anthropic streaming thinking
- Anthropic streaming tool calls

## Current Coupling

AgentRecorder currently depends on pre-merge APIs:

- `OpenAISession`
- `AnthropicSession`
- `FoundationModels.Tool`
- `OpenAIConfiguration.recording`
- `AnthropicConfiguration.recording`
- provider-specific recording model helpers

These need to move to the merged canonical API.

## Target API Shape

Scenarios should use:

```swift
let model = OpenAILanguageModel(
  apiKey: secrets.openAIAPIKey(),
  model: "..."
  // recording transport injected here
)

let session = LanguageModelSession(
  model: model,
  tools: [WeatherTool()],
  instructions: "..."
)
```

The exact initializer can differ, but the scenario should use the merged `LanguageModelSession` and direct provider models, not old SDK-backed session adapters.

## Required Provider Support

Merged providers must support recording transport injection.

Options:

- keep `HTTPReplayRecorder` as the shared recorder
- adapt AnyLanguageModel transport/session protocols to record through `HTTPReplayRecorder`
- create a small provider transport wrapper that records requests and streaming responses

The recorder must continue to support:

- request body capture
- response body capture
- streaming SSE capture
- optional header capture
- redaction or omission of auth headers by default
- pretty-printed JSON output

## Migration Tasks

### Phase A: Preserve Current CLI

- Build AgentRecorder before provider migration.
- Record current scenario list and expected fixture test files.
- Keep current scenarios working until replacement scenarios are ready.

### Phase B: Add Merged Provider Recording Transport

- Add recording transport support to merged provider HTTP layer.
- Verify non-streaming request/response capture.
- Verify streaming response capture.
- Preserve `--include-requests`, `--include-headers`, and pretty-print options.

### Phase C: Rewrite Scenarios

- Rewrite OpenAI scenarios to use `LanguageModelSession` + `OpenAILanguageModel`.
- Rewrite OpenResponses scenarios if needed for OpenResponses-compatible provider tests.
- Rewrite Anthropic scenarios to use `LanguageModelSession` + `AnthropicLanguageModel`.
- Keep scenario IDs stable where possible so existing docs/commands remain useful.
- Update scenario-to-unit-test mappings.

### Phase D: Add New Scenarios

Add scenarios for new merge behavior:

- provider metadata/rate-limit headers where available
- warnings / unsupported optional settings
- structured output source
- transcript-first streaming with tool call deltas
- reasoning streaming

Optional scenarios:

- Gemini live
- Ollama local
- SystemLanguageModel if a recordable transport makes sense

### Phase E: Validate Fixtures

- Regenerate fixtures intentionally.
- Review request/response shape changes as API behavior.
- Update replay tests.
- Confirm replay tests pass without credentials.

## Tests

AgentRecorder should have coverage for:

- option parsing
- scenario catalog lookup
- fixture snippet formatting
- partial recording output on failure
- recording transport for non-streaming responses
- recording transport for streaming responses

Provider scenario correctness should be covered by replay tests generated from AgentRecorder output.

## Exit Criteria

- AgentRecorder builds after provider SDK adapters are removed.
- AgentRecorder scenarios use the merged `LanguageModelSession` and provider models.
- OpenAI and Anthropic replay fixtures can be regenerated.
- Replay tests pass without live credentials.
- CLI help and scenario list remain accurate.

