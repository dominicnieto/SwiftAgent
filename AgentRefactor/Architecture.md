# SwiftAgent Refactor Architecture

## Goal

Create a foundation where provider adapters are cheap to add, streaming and non-streaming tool use share one runtime path, and future agent features such as memory and handoffs can be added without moving provider responsibilities again.

This refactor does not build memory, handoffs, or new providers. It designs the seams so those features can be added later without reworking the core runtime.

## Architecture Chart

```mermaid
flowchart TB
  App[App Code]

  subgraph PublicAPIs[Public APIs]
    LMS[LanguageModelSession\nstateful model conversation]
    AS[AgentSession\nsingle-agent task runtime]
  end

  subgraph SharedRuntime[Shared Runtime]
    CE[ConversationEngine\ntranscript + provider state + request building]
    TE[ToolExecutionEngine\ntool validation + execution + policy]
    ER[EventReducer\nmodel events -> transcript/events/snapshots]
  end

  subgraph ProviderLayer[Provider Layer]
    LM[LanguageModel\nprovider/model adapter protocol]
    PC[ProviderContinuation\nopaque provider-native turn state]
    TR[Transport\nHTTP/SSE/auth/retry]
  end

  subgraph SchemaLayer[Typed Schema Layer]
    SS[@SessionSchema\ntranscript resolver metadata]
    GEN[@Generable / StructuredOutput]
  end

  App --> LMS
  App --> AS

  LMS --> CE
  AS --> CE
  AS --> TE
  AS --> ER
  LMS --> ER

  CE --> LM
  LM --> PC
  LM --> TR

  SS --> CE
  GEN --> LM
  GEN --> TE
```

## Future Orchestration Boundary

This refactor does not build multi-agent orchestration. The architecture should still keep room for it by treating `AgentSession` as one agent runtime, not the whole agent system.

Future orchestration should likely live above `AgentSession`:

```text
AgentOrchestrator / AgentSystem
  owns multiple AgentSession instances
  routes handoffs
  coordinates shared session/memory state
  merges/cancels event streams
  applies workflow policy
```

Early handoffs may be represented as provider-neutral tools inside `AgentSession`, but this refactor does not decide or build that behavior. Provider adapters must not know about handoffs or multi-agent routing.

## Responsibility Split

### LanguageModel

Provider adapter. It talks to one model provider and translates between SwiftAgent's neutral request/response model and provider wire formats.

Owns:

- Request serialization.
- Response parsing.
- Stream event parsing.
- Tool schema serialization.
- Tool call parsing.
- Tool output serialization.
- Provider-native continuation state preservation.
- Provider metadata, usage, warnings, rate limits.

Does not own:

- Tool execution.
- Agent loop.
- Max iterations.
- Memory.
- Handoffs.
- Transcript mutation policy beyond returning events/results.

### ConversationEngine

Shared internal runtime used by both `LanguageModelSession` and `AgentSession`.

Owns:

- Public transcript state.
- Provider continuation state store.
- Building `ModelRequest` from transcript, prompt, options, tools, and continuation state.
- Reducing `ModelResponse` and `ModelStreamEvent` into transcript updates.
- Accumulating token usage and response metadata.
- Mapping structured output snapshots.
- Keeping provider-native state separate from public transcript.

Does not own:

- Tool execution decisions.
- Autonomous loop stop/continue policy.
- Memory retrieval.
- Handoffs.

### LanguageModelSession

Stateful model conversation. It is for direct LLM calls with conversation history and transcript support.

Owns:

- A `ConversationEngine`.
- Simple `respond` and `streamResponse` APIs.
- Instructions and conversation state.
- Structured output convenience APIs.
- Public transcript access.
- Observation state such as `isResponding`, `transcript`, `tokenUsage`, and `responseMetadata`.

Does not own:

- Automatic tool execution.
- Agent loop.
- Tool retries/approvals/max tool rounds.
- Memory/handoff orchestration.

Tool schemas may be passed to a `LanguageModelSession` request when the caller wants the model to produce tool calls, but the session should return those calls rather than execute them automatically.

### AgentSession

Single-agent runtime. It is for task execution with tools.

Owns:

- A `ConversationEngine`.
- Registered tools.
- Tool execution policy.
- Tool loop.
- Max iterations.
- Agent result metadata.
- Agent event stream.
- Stop/cancel/error behavior.

Future integration considerations:

- Memory.
- Handoffs.
- Guardrails.
- Tool approvals.
- Multi-agent orchestration.

These are not implementation targets for this refactor. The only requirement is that this refactor should not put provider, tool-loop, or transcript responsibilities in places that would block those features later.

Does not own:

- Provider wire formats.
- Provider request serialization.
- Provider stream parsing.

## Data Flow

### Direct Model Conversation

```text
App
  -> LanguageModelSession.respond
  -> ConversationEngine builds ModelRequest
  -> LanguageModel sends provider request
  -> LanguageModel returns ModelResponse
  -> ConversationEngine records transcript/usage/metadata/provider state
  -> LanguageModelSession returns response
```

### Agent Tool Loop

```text
App
  -> AgentSession.run
  -> ConversationEngine builds ModelRequest with tool definitions
  -> LanguageModel returns ModelResponse with tool calls and provider continuation state
  -> AgentSession executes tools through ToolExecutionEngine
  -> ConversationEngine builds continuation ModelRequest with tool outputs + provider continuation
  -> LanguageModel continues provider request
  -> repeat until final answer or stop condition
```

### Streaming Agent Tool Loop

```text
App
  -> AgentSession.stream
  -> ConversationEngine builds ModelRequest
  -> LanguageModel streams ModelStreamEvent values
  -> EventReducer emits AgentEvent values and updates transcript
  -> when tool calls complete:
       AgentSession executes tools
       ConversationEngine builds continuation request
       LanguageModel starts next stream
  -> repeat until final answer or stop condition
```

## Provider Continuation State

The public transcript is not enough to continue every provider correctly. Provider continuation state must be stored explicitly.

Examples:

- OpenAI Responses: raw output items such as `reasoning` and `function_call`.
- OpenAI Chat Completions: assistant message with `tool_calls`.
- Anthropic: assistant content blocks such as `thinking`, `tool_use`, and signatures.

The runtime should treat this state as opaque. The provider creates it, the `ConversationEngine` stores it, and the provider consumes it on continuation.

## Session Schema Compatibility

`@SessionSchema` should continue to work with both `LanguageModelSession` and `AgentSession` because it resolves the public `Transcript`, not a specific runtime type.

Refactor direction:

- Keep schema macros focused on transcript decoding.
- Keep `@Tool`, `@Grounding`, and `@StructuredOutput` mapped to transcript entries.
- Rename protocol internals from `LanguageModelSessionSchema` to a runtime-neutral name such as `TranscriptSchema` during the refactor.
- Do not require schema macros to know whether the transcript came from direct conversation or an agent run.
