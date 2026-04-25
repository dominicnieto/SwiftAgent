# Package Layout Spec

## Purpose

Define the intended SwiftPM target/product layout after AnyLanguageModel is moved into SwiftAgent.

## Direction

The final public API should be folded into SwiftAgent. AnyLanguageModel should not remain a separate user-facing package/module long term.

Temporary target boundaries are allowed during migration if they make the copy/build/refactor sequence safer.

## Phase 1 Layout

Initially copy the whole AnyLanguageModel repo into SwiftAgent without rewriting files.

Possible temporary layout:

```text
External/
  AnyLanguageModel/
    Package.swift
    Sources/
    Tests/
    README.md
    ...
```

The exact folder can change, but the important rule is: copy the entire repo first, build it, then prune or relocate.

## Final Core Layout

The base `SwiftAgent` product should include:

- model primitives
- `LanguageModel`
- `LanguageModelSession`
- transcript
- generation options
- prompt/instructions
- tools
- schema/generation support
- macros needed by the core API
- common cloud provider support when lightweight enough
- HTTP transport and replay recording support

Preferred public import:

```swift
import SwiftAgent
```

## Provider Products

Heavy or platform-specific providers should be opt-in.

Recommended product shape:

```swift
.library(name: "SwiftAgent", targets: ["SwiftAgent"]),
.library(name: "SwiftAgentMLX", targets: ["SwiftAgentMLX"]),
.library(name: "SwiftAgentLlama", targets: ["SwiftAgentLlama"]),
```

Potential targets:

```text
Sources/
  SwiftAgent/
  SwiftAgentMacros/
  SwiftAgentMLX/
  SwiftAgentLlama/
  SwiftAgentCoreML/
```

Use separate optional provider targets/products for heavy local providers:

- MLX
- Llama
- other native/local runtimes with large or platform-sensitive dependencies

Use SwiftPM traits only where they genuinely simplify conditional dependencies.

## Provider Placement

Cloud providers with lightweight dependencies can live in the base target if they do not force large optional dependencies.

Providers to preserve as distinct types:

- `OpenAILanguageModel`
- `OpenResponsesLanguageModel`
- `AnthropicLanguageModel`
- `GeminiLanguageModel`
- `OllamaLanguageModel`
- `SystemLanguageModel`
- `CoreMLLanguageModel`
- `MLXLanguageModel`
- `LlamaLanguageModel`

Do not merge `OpenAILanguageModel` and `OpenResponsesLanguageModel` into one provider unless a later design decision explicitly chooses that.

## AgentRecorder Layout

AgentRecorder should continue to build as a macOS CLI target/project.

It should depend on the merged SwiftAgent provider/session API and the replay recorder transport.

It should not depend on removed provider SDK adapters.

## Test Layout

Tests should be grouped by concern:

```text
Tests/
  SwiftAgentTests/
    Core/
    Transcript/
    Streaming/
    Providers/
    Replay/
    AgentRecorder/
  SwiftAgentMacroTests/
  SwiftAgentMLXTests/        # optional
  SwiftAgentLlamaTests/      # optional
```

Moved AnyLanguageModel tests should first be copied intact, then relocated into this layout after they compile.

## Exit Criteria

- `import SwiftAgent` exposes the canonical core API.
- optional local providers do not affect base builds.
- AgentRecorder builds against merged providers.
- tests are discoverable by concern.

