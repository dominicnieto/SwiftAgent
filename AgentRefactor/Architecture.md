# SwiftAgent Refactor Architecture

Last verified: 2026-04-29.

## Goal

Create a public stack where apps can use one model backend directly, wrap it in a stateful low-level session, or run a high-level agent loop without providers owning tools or loops.

Current stack:

```text
AgentSession
  -> LanguageModelSession
  -> ConversationEngine
  -> LanguageModel
```

`ProviderContinuation` is intentionally not part of this fork. Provider-specific state is preserved as `providerMetadata` on model messages, transcript entries, tool calls, reasoning entries, response metadata, attachments, sources, and files.

## Public Layers

### LanguageModel

Lowest public model backend interface. It performs one provider turn at a time.

Owns:

- Provider request serialization.
- Provider response parsing.
- Provider stream parsing.
- Provider tool schema serialization.
- Provider-specific metadata preservation.
- Usage, finish reason, warnings, HTTP metadata, and raw provider diagnostics.

Does not own:

- Local SwiftAgent tool execution.
- Agent loops.
- Max iterations.
- Handoffs, routing, memory, approvals, or retries.
- Public transcript mutation.

### LanguageModelSession

Public stateful low-level session around a `LanguageModel`.

Owns:

- A private `ConversationEngine`.
- Transcript, token usage, response metadata, and observation state.
- Direct `respond` and `streamResponse` APIs.
- Explicit tool-output continuation APIs:
  - `respond(with toolOutputs:)`
  - `streamResponse(with toolOutputs:)`
- Structured output, image, prompt, grounding, and schema convenience APIs.

Does not own:

- Automatic local tool execution.
- Agent loop policy.
- Tool retries, missing-tool policy, or approvals.

Tool definitions may be registered so the model can emit tool calls. App code using `LanguageModelSession` must inspect tool calls and provide tool outputs explicitly.

### AgentSession

Public high-level single-agent runtime.

Owns:

- A `LanguageModelSession`.
- Registered local tools.
- Tool execution policy.
- Non-streaming and streaming model/tool loops.
- Max-iteration protection.
- Per-step history.
- Agent event stream.
- Durable observable state.

Does not own:

- Provider wire formats.
- Provider request serialization.
- Provider stream parsing.
- Provider-defined/server-side tool execution.

Future handoffs/routing/orchestration should live above `AgentSession` by coordinating multiple `AgentSession` instances or by adding explicit orchestration types later.

## Internal Runtime

### ConversationEngine

Package-internal actor owned by `LanguageModelSession`.

Owns:

- Public transcript state.
- Request building from transcript, prompt, tool outputs, tools, structured output, images, and options.
- Reduction of `ModelResponse` and `ModelStreamEvent` into transcript updates.
- Token usage and response metadata accumulation.
- Streaming snapshots for both public session streaming and agent runtime hooks.

It does not store a separate continuation object. Provider-specific continuity data remains attached to the transcript/model parts that providers need to reconstruct their next request.

### Runtime Hooks

`AgentSession` depends on package-level hooks exposed by `LanguageModelSession`, not on `ConversationEngine` directly:

- `modelResponseForRuntime(...)`
- `modelStreamForRuntime(...)`
- `applyRuntimeResponse(...)`

This keeps `ConversationEngine` behind `LanguageModelSession` while still letting the agent runtime use lower-level turn events.

## Data Flow

### Direct Model Turn

```text
App
  -> LanguageModelSession.respond
  -> ConversationEngine builds ModelRequest
  -> LanguageModel sends provider request
  -> LanguageModel returns ModelResponse
  -> ConversationEngine records transcript/usage/metadata
  -> LanguageModelSession returns response
```

### Manual Tool Continuation With LanguageModelSession

```text
App
  -> LanguageModelSession.respond
  -> model returns tool calls
  -> app executes or rejects tools
  -> app calls respond(with toolOutputs:)
  -> ConversationEngine records tool outputs and builds next ModelRequest
  -> LanguageModel serializes provider-native tool output shape using providerMetadata
```

### Agent Tool Loop

```text
App
  -> AgentSession.run or AgentSession.stream
  -> AgentSession calls LanguageModelSession runtime hook for one model turn
  -> model returns text/reasoning/tool calls/events
  -> AgentSession executes local tool calls
  -> AgentSession passes tool outputs back through LanguageModelSession
  -> repeat until final answer, max iterations, cancellation, or error
```

## Provider State Model

The public transcript is still the durable conversation record, but provider-native fields are preserved inside `providerMetadata`.

Examples:

- OpenAI Responses: `response_id`, `item_id`, `call_id`, raw response items, encrypted reasoning content.
- OpenAI Chat Completions: assistant tool-call message metadata and tool call IDs.
- Anthropic: `tool_use_id`, thinking signatures, assistant content block metadata.

Rules:

- Provider metadata is part of the public model/transcript data shape because direct `LanguageModel` and `LanguageModelSession` use must preserve provider fidelity.
- Normal app code usually does not need to inspect provider metadata.
- Providers must keep basic text/tool loops working when possible, but advanced provider-native features can degrade if caller-created transcript/model messages omit required provider metadata.
- `ProviderContinuation` must not be reintroduced unless the public API design is reopened deliberately.

## Session Schema Compatibility

`@SessionSchema` resolves shared `Transcript` values and works with both public session APIs.

Current schema layer:

- Public macro remains `@SessionSchema`.
- Runtime-neutral protocol is `TranscriptSchema`.
- `LanguageModelSessionSchema` is removed.
- Groundings, tool calls, tool outputs, reasoning, and structured output resolve from transcript entries, not from a specific session runtime.
