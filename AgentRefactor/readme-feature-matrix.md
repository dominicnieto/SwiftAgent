# README Feature Matrix

Last verified: 2026-04-29.

Phase 8 should use this as the README rewrite map. Phases 1-7 are complete in the forked architecture:

```text
AgentSession -> LanguageModelSession -> ConversationEngine -> LanguageModel
```

Provider-specific continuity is preserved through `providerMetadata`, not `ProviderContinuation`.

## Feature Ownership

| README area | Current README surface | Refactor owner | Required change |
| --- | --- | --- | --- |
| SwiftAgent in Action | `LanguageModelSession(model:tools:instructions:)` runs tools and structured output | `AgentSession` | Move the example to `AgentSession` because it depends on automatic tool execution. Keep `@SessionSchema` transcript resolution. |
| Features list: Zero-Setup Agent Loops | Main session owns agent loops | `AgentSession` | Rewrite to name `AgentSession` as the zero-setup agent loop API. |
| Features list: Native Tool Integration | Tool integration implied on main session | `AgentSession` for execution; `LanguageModelSession` for manual tool-call inspection only | Split tool schema serialization from automatic execution. |
| Basic Usage | Plain `LanguageModelSession.respond` with Open Responses and Anthropic | `LanguageModelSession` | Keep. This is direct stateful model conversation. |
| Building Tools | `LanguageModelSession` with `tools: [WeatherTool()]` executes tool | `AgentSession` | Move automatic tool execution example to `AgentSession`. Add a smaller `LanguageModelSession` note only for passing tool schemas and inspecting returned calls if that API remains public. |
| Recoverable Tool Rejections | Tool rejection is forwarded through session-owned loop | `AgentSession` | Move to `AgentSession`; preserve rejection envelope behavior in tool execution engine/tests. |
| Structured Responses | Structured response example currently includes tools on `LanguageModelSession` | Both, depending on tool use | Keep direct structured output on `LanguageModelSession` when no automatic tools are needed. Use `AgentSession` when structured final output depends on tool execution. |
| Access Transcripts | `LanguageModelSession.transcript` includes prompts, reasoning, tool calls, tool outputs, responses | Both | Keep transcript access on `LanguageModelSession`; add `AgentSession.transcript` for tool runs. Tool-output examples should use `AgentSession`. |
| Access Token Usage | Session and response token usage | Both | Keep on `LanguageModelSession`; add/verify `AgentSession` aggregates usage across model/tool iterations. |
| Prompt Builder | Prompt DSL used with `LanguageModelSession.respond` | Shared, exposed by both | Keep current `LanguageModelSession` example. Agent prompts should use the same prompt/model request layer. |
| Custom Generation Options | Provider-specific options on `LanguageModelSession.respond` | Both | Keep direct model-call examples on `LanguageModelSession`. Agent runs should forward the same options per model turn. |
| Session Schema overview | Says `LanguageModelSession` remains the runtime | Transcript/schema layer, both sessions | Rewrite to say `@SessionSchema` resolves shared `Transcript` values from either public session. |
| Session Schema: Tools | Resolves tool runs from `LanguageModelSession.transcript` | `AgentSession` for automatic tool runs | Move automatic tool-run example to `AgentSession`; keep resolver API unchanged. |
| Session Schema: Structured Output Entries | Structured output and tool schema example on `LanguageModelSession` | Both | Keep non-tool structured output on `LanguageModelSession`; use `AgentSession` when tools are registered for execution. |
| Session Schema: Groundings | Prompt groundings with `LanguageModelSession` | Both | Keep `LanguageModelSession` example and add note/example for `AgentSession` after it exists. |
| Streaming Responses | Text says stream while agent thinks, calls tools, and finalizes | Split | Direct text/structured streaming remains `LanguageModelSession.streamResponse`. Tool-call/reasoning/tool-output event streaming moves to `AgentSession.stream`. |
| Streaming Structured Outputs | Structured streaming with tools on `LanguageModelSession` | Both | Keep direct structured streaming for `LanguageModelSession`; move tool-backed structured final output streaming to `AgentSession`. |
| Streaming State Helpers | Tool run projections and structured output snapshots | Both, with tool helpers primarily `AgentSession` | Tool-run helpers remain relevant to `AgentSession` transcripts. Structured output helpers remain shared transcript concepts. |
| Proxy Servers | Proxy setup with `OpenResponsesLanguageModel` and `LanguageModelSession` | `LanguageModelSession`, also usable by `AgentSession` | Keep direct example. Add that the same model/HTTP client can be passed to `AgentSession`. |
| Per-turn Authorization | Per-call token with `respond`/`streamResponse` | Both | Keep for direct model calls. Agent loops should document that options/auth apply to each model turn in the loop. |
| Simulated Session | `SimulationLanguageModel` with `LanguageModelSession` and configured tool run | Simulated provider plus both sessions | Keep deterministic direct simulation. Add Phase 6 decision: use simulation as a provider for engine tests and `AgentSession` scenarios. |
| Logging | Logs describe agent start/tool calls/finish | `AgentSession` for tool loop logs; providers/session for direct calls | Split direct model-call logs from agent tool-loop logs. |
| Recording HTTP Fixtures | Recorder example uses `LanguageModelSession` | Both | Keep direct fixture recording on `LanguageModelSession`; add `AgentSession` scenarios for streaming tool calls after Phase 5. |
| Example App | Agent Playground uses current session/tool loop | Both | Phase 8 should add OpenAI/Anthropic menu or mode selector for direct `LanguageModelSession` vs automatic `AgentSession`. |

## Examples That Should Stay On LanguageModelSession

| Example/feature | Reason |
| --- | --- |
| Basic text response with Open Responses | Single model turn, no automatic tool execution. |
| Basic text response with Anthropic | Single model turn, no automatic tool execution. |
| Plain structured response without tools | Direct model generation with provider-native response format. |
| Prompt builder | Direct prompt rendering belongs to the shared request layer and is valid for a direct session. |
| Custom generation options | Provider options apply to direct model calls and should not require an agent. |
| Access token usage for a single response | Direct session already exposes response/session usage. |
| Proxy server setup for direct Responses calls | It demonstrates HTTP client/auth configuration, not an agent loop. |
| Direct streaming text | `LanguageModelSession.streamResponse` remains the direct model streaming API. |
| Direct streaming structured output | Remains a model/engine feature when no tools are executed. |
| Grounded prompt examples | Groundings are prompt/transcript metadata, not agent-specific. |

## Examples That Should Move To AgentSession

| Example/feature | Reason |
| --- | --- |
| SwiftAgent in Action | Registers tools and expects the runtime to call them. |
| Building Tools | The example asks a question that requires automatic tool execution. |
| Recoverable Tool Rejections | Rejections only make sense inside a tool execution loop that can continue after the model corrects itself. |
| Tool run resolution in Session Schema | Automatic tool calls and outputs should be produced by `AgentSession`. |
| Streaming while the agent thinks/calls tools | This is agent event streaming, not direct model streaming. |
| Tool-run streaming state helpers | They describe live tool arguments/output generated by an agent loop. |
| Example app Agent Playground flow | It demonstrates automatic tool execution, reasoning, and transcript UI. |
| Token usage aggregation across tool iterations | This is a multi-turn agent-run result concern. |

## Features Shared By Both Public Sessions

| Shared feature | Notes |
| --- | --- |
| Transcript access | Both sessions should expose the same public `Transcript` shape. |
| `@SessionSchema` transcript resolution | The macro name can remain, but generated protocol internals should become runtime-neutral. |
| Structured output decoding | Direct sessions and agent final results should both support `@Generable` outputs. |
| Prompt builder and groundings | Both should feed the shared request builder/conversation engine. |
| Image input | Both should pass attachments through `ModelRequest` when the provider supports images. |
| Token usage and response metadata | Direct sessions expose latest/cumulative usage; agents aggregate across iterations and expose latest/per-run metadata. |
| Reasoning summaries | Providers parse reasoning; the engine records it; both sessions can expose it through transcript/events. |

## Additional README Requirements From Fork

| Required section | Content |
| --- | --- |
| `LanguageModel` | Explain direct one-turn model backend use. Mention that manual multi-turn use must preserve `providerMetadata` for provider-native fidelity. |
| Provider metadata | Explain that metadata is not normal app UI content, but it is part of the durable model/transcript state when callers manually manage turns. |
| OpenAI `store` | Explain SwiftAgent omits `store` unless set; OpenAI Responses stores by default; `store: false` may require encrypted reasoning metadata for full reasoning continuity. |
| Provider feature gaps | Link to provider `FEATURE_PARITY.md` files rather than claiming full OpenAI/Anthropic parity. |
