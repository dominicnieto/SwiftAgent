# Phase 9 Results

Date: 2026-04-29

## Scope

Phase 9 hardened the refactored runtime without reopening the architecture:

```text
AgentSession -> LanguageModelSession -> ConversationEngine -> LanguageModel
```

`ProviderContinuation` remains absent. Provider-native continuity continues to live in `providerMetadata`, raw provider payloads, and transcript/model values.

## Completed

- Added public provider-tool plumbing through `providerTools: [ToolDefinition]` on `LanguageModelSession` and `AgentSession`.
- Added `ToolDefinition.providerDefined(name:providerMetadata:description:)`.
- Updated `ConversationEngine` request construction so provider-defined tools are sent to models alongside local tool definitions.
- Kept `AgentSession` execution scoped to local Swift tools. Provider-defined tool calls pass through and are not treated as missing local tools.
- Added OpenAI Responses options:
  - `previousResponseID`
  - `conversation`
  - typed `include`
  - conflict validation for `previousResponseID` plus `conversation`
  - automatic `reasoning.encrypted_content` include when `store == false` and reasoning continuity requires it
- Added bounded OpenAI hosted tool helpers for web search, file search, and code interpreter request shapes.
- Added Open Responses typed `include` support and raw provider-defined tool request support.
- Added Anthropic server tool request helpers for web search, web fetch, code execution, memory, and raw fallback.
- Added Anthropic per-request beta merging, `disable_parallel_tool_use`, and adaptive/disabled thinking request modes.
- Updated provider request/parsing paths so provider-defined tool calls preserve provider metadata and flow through the neutral model surface.
- Audited and updated README/provider parity docs for tool ownership and provider-tool behavior.

## Tests Added

- Conversation engine request coverage for provider-defined tools.
- Agent session coverage proving provider tools are passed through to the underlying model session.
- OpenAI request coverage for continuation options, include handling, hosted tool metadata, and invalid continuation configuration.
- Open Responses request coverage for include and raw provider-defined tool metadata.
- Anthropic request coverage for server tools, per-request betas, thinking modes, and `disable_parallel_tool_use`.

## Verification

- `swift test` passed: 148 tests.
- `xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests -testPlan SwiftAgentTests test -quiet` passed.
- `xcodebuild -workspace SwiftAgent.xcworkspace -scheme SwiftAgentTests build -quiet` passed.
- `xcodebuild -workspace SwiftAgent.xcworkspace -scheme ExampleApp -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" build -quiet` passed.
- `xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS,arch=arm64" -derivedDataPath .tmp/DerivedData-phase9-recorder build -quiet` passed.
- `./.tmp/DerivedData-phase9-recorder/Build/Products/Debug/AgentRecorder --list-scenarios` passed.
- `swiftformat --config ".swiftformat" {changed Swift files}` was not run because `swiftformat` was not installed in this environment.

## Boundary Test Decision

A public symbol graph boundary test was attempted, but removed from the test suite. It required running `swift package dump-symbol-graph` from inside a Swift test, which was fragile under `swift test` because it nested SwiftPM dependency resolution/build work inside the package test process.

The runtime boundary is still enforced structurally by access control in source (`package`/internal runtime types and public session/provider APIs). If symbol graph auditing is needed later, it should run as a CI or release-check script rather than as a normal unit test.

## Follow-Up Work

- OpenAI compaction API.
- OpenAI computer use.
- Remote MCP.
- Full logprobs normalization.
- Complete hosted/server tool result normalization for sources, files, citations, and usage counters.
- Anthropic text editor/computer use.
- Complete provider token-counting APIs.
- Live AgentRecorder fixtures for hosted/server tools when deterministic provider access is available.
