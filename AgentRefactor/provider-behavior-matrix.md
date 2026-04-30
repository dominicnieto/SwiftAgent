# Provider Behavior Matrix

Last verified: 2026-04-29.

This matrix tracks the current fork after phases 1-7. Detailed provider-doc and AI SDK parity gaps now live beside each provider implementation:

- `Sources/SwiftAgent/Providers/OpenAI/FEATURE_PARITY.md`
- `Sources/SwiftAgent/Providers/OpenResponses/FEATURE_PARITY.md`
- `Sources/SwiftAgent/Providers/Anthropic/FEATURE_PARITY.md`
- `Sources/SimulatedSession/Simulation/FEATURE_PARITY.md`

## Provider/API Variants

| Provider/API variant | Type | API path | Notes |
| --- | --- | --- | --- |
| OpenAI Chat Completions | `OpenAILanguageModel(apiVariant: .chatCompletions)` | `POST chat/completions` | Default `OpenAILanguageModel` variant. Basic streaming text, local function tools, structured output, image input. |
| OpenAI Responses | `OpenAILanguageModel(apiVariant: .responses)` | `POST responses` | Official OpenAI Responses API path. Supports Responses text, structured output, local tool calls, streamed tool arguments, reasoning entries, encrypted reasoning when returned. |
| Open Responses compatible API | `OpenResponsesLanguageModel` | `POST responses` at configurable `baseURL` | Responses-shaped compatible endpoint. Provider variability is tracked in its feature parity matrix. |
| Anthropic Messages | `AnthropicLanguageModel` | `POST v1/messages` | Anthropic Messages API with text, image input, local tools, streamed tool JSON, structured output, thinking/signature support. |
| Simulated provider | `SimulationLanguageModel` in `SimulatedSession` | In-process deterministic model | Test/preview provider. No external provider-doc parity target. |

## Current Behavior

| Behavior | OpenAI Chat | OpenAI Responses | Open Responses | Anthropic | Simulation |
| --- | --- | --- | --- | --- | --- |
| Text generation | Yes | Yes | Yes | Yes | Yes |
| Structured output | Yes | Yes | Yes | Yes | Yes |
| Image input | Yes | Yes | Yes | Yes | No current image simulation path |
| Local tool definitions | Yes | Yes | Yes | Yes | Mock tool runs |
| Local tool calls | Non-streaming yes | Yes | Yes | Yes | Simulated |
| Provider executes local tools | No | No | No | No | No |
| `AgentSession` executes local tools | Yes | Yes | Yes | Yes | Yes |
| Streaming text | Yes | Yes | Yes | Yes | Yes |
| Streaming tool-call input | No for Chat | Yes | Yes when endpoint matches expected events | Yes | No provider-native delta simulation |
| Reasoning/thinking | No parsed reasoning | Yes when returned | Yes when returned | Yes thinking/signature when returned | Configured reasoning entries |
| Provider-defined/server tools | Not first-class | Not first-class | Not first-class | Not first-class | Not applicable |
| Usage | Non-streaming | Non-streaming and streaming | Non-streaming and streaming | Non-streaming and streaming | Configured usage |
| HTTP/provider metadata | Yes | Yes | Yes | Yes | Basic provider/model metadata |

## Provider State Model

The old plan described a separate `ProviderContinuation` object. That is no longer the architecture.

Current rule:

- Provider-specific state is preserved through `providerMetadata` and raw provider output on model/transcript values.
- Providers reconstruct their native follow-up request from neutral messages, transcript entries, tool outputs, and provider metadata.
- `LanguageModelSession` and `AgentSession` both use the same transcript/provider-metadata path.

Examples:

| Provider | Provider metadata currently used for |
| --- | --- |
| OpenAI Chat | Assistant message/tool call metadata, `call_id`/tool IDs. |
| OpenAI Responses | `response_id`, `item_id`, `call_id`, encrypted reasoning content, raw output item metadata. |
| Open Responses | Responses-style `item_id`, `call_id`, encrypted reasoning content, raw output item metadata. |
| Anthropic | `tool_use_id`, thinking signatures, content-block metadata. |
| Simulation | Minimal provider/model identity and configured transcript entries. |

## Remaining Provider Gaps

These are not blockers for phases 1-7, but they are phase-8/phase-9 documentation and hardening inputs:

- OpenAI first-class `previous_response_id`, `conversation`, and `include`.
- OpenAI automatic `reasoning.encrypted_content` include when `store: false` and reasoning continuity needs it.
- OpenAI hosted tools: web search, file search, code interpreter, citations, annotations, logprobs.
- Anthropic server tools, containers, context management, redacted thinking, and hosted web/search/code/memory features.
- More request-body and stream replay tests for provider-specific metadata preservation.

## Responsibility Checks

| Check | Current status |
| --- | --- |
| Providers implement neutral `LanguageModel` turn API | Complete |
| Providers depend on `LanguageModelSession` | No |
| Providers execute local tools | No |
| `LanguageModelSession` executes local tools | No |
| `AgentSession` owns local tool execution loop | Yes |
| `AgentSession` owns `LanguageModelSession` rather than `ConversationEngine` directly | Yes |
| `@SessionSchema` works from both public sessions | Yes |
