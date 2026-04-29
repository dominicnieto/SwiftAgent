# Anthropic Provider Feature Parity

Sources used: Anthropic Messages, tool-use, streaming, extended-thinking, web-search, context-management/container docs; local AI SDK Anthropic provider sources under `.context/attachments/extracted/ai-main/packages/anthropic/src`.

| Feature | Provider docs behavior | AI SDK behavior | SwiftAgent current behavior | Gap | Priority | Tests needed |
| --- | --- | --- | --- | --- | --- | --- |
| Messages text | Messages API returns text content blocks. | Supported. | Supported. | None for basic text. | Done | Existing fixture. |
| Streaming text | Streams message/content block events and text deltas. | Maps to typed stream parts. | Supports text start/delta/completion. | Needs latest event audit. | Medium | SSE replay. |
| Structured output | Anthropic supports structured outputs/tool-style JSON schema approaches. | Supports structured output. | Sends `output_config.format` JSON schema and decodes text JSON. | Need verify current docs/wire shape for latest API. | High | Request/response fixture. |
| Image input | Messages content supports image blocks. | Supported. | Supported for URL/base64 image segments. | Need edge coverage for media types. | Medium | Multimodal request fixture. |
| Local tools | Tool definitions produce `tool_use`; callers return `tool_result`. | Supported. | Supported non-streaming and streaming input JSON deltas. | Need stronger continuation tests for multiple/interleaved tools. | High | Multi-tool replay. |
| Tool choice | Anthropic has auto/any/tool/none tool choice modes. | Supported. | Supported. | Missing `disable_parallel_tool_use` option despite coding key presence. | Medium | Request tests. |
| Fine-grained tool streaming | Anthropic can stream tool input with beta-gated behavior. | Supports streaming tool deltas. | Supports `input_json_delta` accumulation. | Beta-specific behavior not fully tested. | Medium | Beta streaming fixture. |
| Extended thinking | Thinking blocks and signatures must be preserved with tool use. | Supports enabled/adaptive/disabled thinking, signatures, redacted thinking. | Supports enabled thinking option and streams thinking/signature into reasoning. | Missing adaptive/disabled modes and full thinking-block replay audit. | High | Thinking + tool-use fixture. |
| Redacted thinking | API may emit redacted thinking blocks. | Models redacted thinking. | Not first-class. | Missing. | Medium | Decode fixture. |
| Interleaved thinking | Tool use can interleave thinking between tool calls with beta behavior. | Supports related provider options. | Not first-class beyond generic thinking deltas. | Missing. | Medium | Interleaved fixture. |
| Server web search | Anthropic hosted web search emits `server_tool_use`, web search results, and usage counters. | Models web search tool/result parts and usage. | Not first-class. | Missing. | High | Web-search fixture after API added. |
| Web fetch/code execution/memory | Anthropic server tools can emit provider-owned tool use/results. | AI SDK has coverage for server tool parts in fixtures/code. | Not first-class. | Missing. | Medium | Server-tool fixtures after API added. |
| Containers | Anthropic container IDs can be forwarded between steps. | AI SDK models and has helper to forward container IDs. | Not first-class. | Missing. | Medium | Metadata decode + request forwarding test. |
| Context management | API can clear tool results/thinking and reports applied edits. | AI SDK exposes context-management options and metadata. | Not first-class. | Missing. | Medium | Request/decode fixture. |
| Citations | Web/search outputs can include citation metadata. | AI SDK maps citation metadata. | Not fully normalized. | Missing. | Medium | Citation decode fixture. |
| Usage/HTTP metadata | Messages responses include usage and may include server-tool usage details. | Preserves token and provider metadata. | Preserves token usage and HTTP metadata; server-tool usage not fully modeled. | Partial. | Medium | Usage fixture with server-tool usage. |

