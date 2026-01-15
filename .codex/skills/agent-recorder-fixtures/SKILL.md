---
name: agent-recorder-fixtures
description: Record real OpenAI/Anthropic HTTP back-and-forth (including streaming text/event-stream) and print paste-ready Swift fixtures for SwiftAgent unit tests (ReplayHTTPClient) using the AgentRecorder CLI or HTTPReplayRecorder. Use when adding/updating streaming tool-call tests, when provider payload formats change, or when you need to debug request/response mismatches by inspecting recorded JSON/SSE payloads.
---

# Agent Recorder Fixtures

## Overview

Use `AgentRecorder` to capture real provider payloads and generate paste-ready Swift fixtures for tests using `ReplayHTTPClient`.
This is the fastest loop for keeping streaming tool-call tests in sync with real OpenAI/Anthropic SSE traffic.

## Workflow

1) Pick the right scenario
- Existing scenarios live in `AgentRecorder/AgentRecorder/main.swift` (`Scenario.*`).
- If no scenario matches your test, add one (keep it small and deterministic).

2) Set API keys
- OpenAI: `OPENAI_API_KEY`
- Anthropic: `ANTHROPIC_API_KEY`

3) Run the recorder (Xcode or Terminal)
- Xcode: select `AgentRecorder` scheme, set env vars, Run → copy stdout from Debug console.
- Terminal:

```bash
xcodebuild -quiet -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" -derivedDataPath .tmp/DerivedData build
OPENAI_API_KEY=sk-... ./.tmp/DerivedData/Build/Products/Debug/AgentRecorder --provider openai --scenario tool-call-weather-openai
```

4) Paste fixtures into tests
- Output is already formatted for `ReplayHTTPClient(recordedResponses:)`.
- Paste into the relevant test file (common locations):
  - `Tests/SwiftAgentTests/OpenAISession/...`
  - `Tests/SwiftAgentTests/AnthropicSession/...`

5) Run tests
- `xcodebuild -quiet -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test`

## Notes

- Headers may include secrets. `HTTPReplayRecorder` redacts common auth header fields, but always review before committing.
- Streaming fixtures are raw `text/event-stream`. If the SDK stops consuming early, the recorded payload may be partial (this is usually fine for replaying the SDK’s behavior).
- If you need request bodies for debugging, re-run with `--include-requests`.
