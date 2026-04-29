# Simulation Provider Feature Coverage

Simulation is an in-process SwiftAgent provider, so it has no external provider API or AI SDK parity target. This matrix tracks coverage against SwiftAgent's public model/session contracts.

| Feature | Provider docs behavior | AI SDK behavior | SwiftAgent current behavior | Gap | Priority | Tests needed |
| --- | --- | --- | --- | --- | --- | --- |
| Deterministic text | Not applicable. | Not applicable. | Supports configured text responses. | None. | Done | Existing simulation tests/usages. |
| Deterministic structured output | Not applicable. | Not applicable. | Supports configured `GeneratedContent` responses. | None for configured output. | Done | Structured response fixture. |
| Streaming text | Not applicable. | Not applicable. | Emits text start/delta/completed for configured text responses. | Does not simulate token-by-token deltas. | Low | Optional granular streaming test. |
| Streaming structured output | Not applicable. | Not applicable. | Emits structured deltas for configured structured responses. | Does not simulate partial JSON growth. | Low | Optional partial structured test. |
| Mock tool calls | Not applicable. | Not applicable. | Emits configured mock tool call and output transcript entries. | Does not simulate provider-native tool-call argument deltas. | Medium | Tool-call stream test. |
| Reasoning | Not applicable. | Not applicable. | Emits configured reasoning transcript entries. | Uses empty encrypted reasoning placeholder. | Low | Reasoning fixture. |
| Token usage | Not applicable. | Not applicable. | Supports configured token usage. | None. | Done | Existing usage test. |
| Provider metadata | Not applicable. | Not applicable. | Emits provider/model metadata for Simulation. | No custom provider metadata scenarios. | Low | Optional metadata test. |
| Error simulation | Not applicable. | Not applicable. | Missing generations and mock tool failures can throw. | No broad provider error simulation model. | Low | Missing-generation/tool-failure tests. |

