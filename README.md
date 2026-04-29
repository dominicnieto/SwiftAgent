[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSwiftedMind%2FSwiftAgent%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SwiftedMind/SwiftAgent)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSwiftedMind%2FSwiftAgent%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SwiftedMind/SwiftAgent)

# SwiftAgent

**Native Swift SDK for building autonomous AI agents with Apple's FoundationModels design philosophy**

SwiftAgent simplifies AI agent development by providing a clean, intuitive API that handles the complexity of agent loops, tool execution, and direct provider communication. Inspired by Apple's FoundationModels framework, it brings the same elegant, declarative approach to cross-platform AI agent development.

## SwiftAgent in Action

```swift
import SwiftAgent

@SessionSchema
struct CityExplorerSchema {
  @Tool var cityFacts = CityFactsTool()
  @Tool var reservation = ReservationTool()

  @Grounding(Date.self) var travelDate
  @Grounding([String].self) var mustVisitIdeas

  @StructuredOutput(ItinerarySummary.self) var itinerary
}

@MainActor
func planCopenhagenWeekend() async throws {
  let schema = CityExplorerSchema()
  let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
  let session = AgentSession(
    model: model,
    schema: schema,
    instructions: "Design cinematic weekends. Call tools for local intel and reservations.",
  )

  let response = try await session.run(
    to: Prompt {
      PromptTag("context") {
        "Travel date: \(Date(timeIntervalSinceNow: 86_400))"
        "Must-visit ideas:"
        "Coffee Collective, Nørrebro",
        "Designmuseum Denmark",
        "Kødbyens Fiskebar"
      }

      PromptTag("user-query") {
        "Coffee, design, and dinner plans for two days in Copenhagen."
      }
    },
    generating: ItinerarySummary.self,
  )

  print(response.content.headline)
  print(response.content.mustTry.joined(separator: " → "))

  for entry in try schema.resolve(session.transcript) {
    if case let .toolRun(.cityFacts(run)) = entry, let output = run.output {
      print("Local picks:", output)
    }

    if case let .prompt(prompt) = entry {
      print("Groundings:", prompt.sources)
    }
  }
}
```

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
  - [Public API Layers](#public-api-layers)
  - [Installation](#installation)
  - [Basic Usage](#basic-usage)
  - [Building Tools](#building-tools)
  - [Structured Responses](#structured-responses)
  - [Access Transcripts](#access-transcripts)
  - [Access Token Usage](#access-token-usage)
  - [Prompt Builder](#prompt-builder)
  - [Custom Generation Options](#custom-generation-options)
- [Session Schema](#session-schema)
  - [Tools](#tools)
  - [Structured Output Entries](#structured-output-entries)
  - [Groundings](#groundings)
- [Streaming Responses](#streaming-responses)
  - [Streaming Structured Outputs](#streaming-structured-outputs)
- [Streaming State Helpers](#streaming-state-helpers)
- [Proxy Servers](#proxy-servers)
  - [Per-turn Authorization](#per-turn-authorization)
- [Simulated Session](#simulated-session)
- [Logging](#logging)
- [Recording HTTP Fixtures](#recording-http-fixtures)
- [Development Status](#development-status)
- [Example App](#example-app)
- [License](#license)
- [Acknowledgments](#acknowledgments)

## Features

- **Zero-Setup Agent Loops** — Handle autonomous agent execution with just a few lines of code
- **Native Tool Integration** — Use SwiftAgent `@Generable` structs as agent tools seamlessly
- **Provider Agnostic** — The main session API supports multiple AI providers (OpenAI + Anthropic included, more coming)
- **Apple-Native Design** — API inspired by FoundationModels for familiar, intuitive development
- **Modern Swift** — Built with Swift 6, async/await, and latest concurrency features
- **Rich Logging** — Comprehensive, human-readable logging for debugging and monitoring
- **Flexible Configuration** — Fine-tune generation options, tools, and provider-specific settings

## Quick Start

### Public API Layers

SwiftAgent exposes three public layers. Use the lowest layer that matches how much control you want.

#### LanguageModel

`LanguageModel` is the lowest-level model inference backend. It accepts a provider-neutral `ModelRequest` and returns one `ModelResponse`, or streams one turn as `ModelStreamEvent` values.

Use this layer when you are building your own session, transcript, tool loop, or provider adapter:

```swift
let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let response = try await model.respond(to: ModelRequest(
  messages: [
    ModelMessage(
      role: .user,
      segments: [.text(.init(content: "Write one sentence about Swift concurrency."))]
    )
  ]
))
```

When using `LanguageModel` directly across multiple turns, keep the full `ModelMessage`, `ModelResponse`, transcript part, and tool-call values instead of flattening them to plain strings. Providers store API bookkeeping in `providerMetadata`, such as response item IDs, encrypted reasoning payloads, citations, hosted tool references, container IDs, and native tool-call IDs. Basic text loops may still work without that metadata, but provider-specific continuity can degrade.

#### LanguageModelSession

`LanguageModelSession` is a stateful, low-level chat/session API around a `LanguageModel`. It owns transcript state, instructions, tools, schema tools, token usage, response metadata, and streaming snapshots.

It sends tools to the model and records model-emitted tool calls, but it does not execute tools and it does not run an agent loop. After a response contains tool calls, app code can execute whichever tools it wants and explicitly continue with `respond(with: toolOutputs)` or `streamResponse(with: toolOutputs)`.

```swift
let session = LanguageModelSession(
  model: model,
  tools: [WeatherTool()],
  instructions: "Use tools when current weather is needed."
)

let firstTurn = try await session.respond(to: "Weather in Nashville?")

let toolOutputs = firstTurn.transcriptEntries.compactMap { entry -> Transcript.ToolOutput? in
  guard case let .toolCalls(toolCalls) = entry,
        let call = toolCalls.calls.first
  else { return nil }

  return Transcript.ToolOutput(
    id: call.id,
    callId: call.callId,
    toolName: call.toolName,
    segment: .text(.init(content: "72 F and clear")),
    status: .completed
  )
}

let finalTurn = try await session.respond(with: toolOutputs)
print(finalTurn.content)
```

For streaming, use the same one-turn shape with `streamResponse(to:)` and continue through `streamResponse(with: toolOutputs)`.

#### AgentSession

`AgentSession` is the high-level agent runtime. It uses the same model/session primitives, but owns the loop: send a turn, inspect tool calls, execute registered local tools, append tool outputs, and repeat until the model produces a final answer or the configured limits are reached.

Use `AgentSession` when you want SwiftAgent to execute tools and manage the full agent lifecycle:

```swift
let session = AgentSession(
  model: model,
  tools: [WeatherTool()],
  instructions: "Answer with current weather when asked."
)

let response = try await session.run(to: "Weather in Nashville?")
print(response.content)
```

### Installation

Add SwiftAgent to your Swift project:

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/SwiftedMind/SwiftAgent.git", branch: "main")
]

.product(name: "SwiftAgent", package: "SwiftAgent")
```

Then import SwiftAgent:

```swift
import SwiftAgent
```

### Basic Usage

Create a model and a `LanguageModelSession` with your default instructions, then call `respond` whenever you need a single-turn answer. The session tracks conversation state for you, so you can start simple and layer on additional features later.

```swift
import SwiftAgent

let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = LanguageModelSession(
  model: model,
  instructions: "You are a helpful assistant.",
)

// Create a response
let response = try await session.respond(to: "What's the weather like in San Francisco?")

// Process response
print(response.content)
```

Or use Anthropic:

```swift
import SwiftAgent

let model = AnthropicLanguageModel(apiKey: "sk-ant-...", model: "claude-sonnet-4-5")
let session = LanguageModelSession(
  model: model,
  instructions: "You are a helpful assistant.",
)

let response = try await session.respond(to: "What's the weather like in San Francisco?")

print(response.content)
```

> [!NOTE]
> Using an API key directly is great for prototyping, but do not ship it in production apps. For shipping apps, use a secure proxy with per‑turn tokens. See [Proxy Servers](#proxy-servers) for more information.

### Building Tools

Create tools using SwiftAgent's `@Generable` macro for type-safe tool definitions. Tools expose argument and output types that SwiftAgent validates for you, so `AgentSession` can execute model-requested tools and return strongly typed results without manual JSON parsing.

```swift
import SwiftAgent

struct WeatherTool: Tool {
  let name = "get_weather"
  let description = "Get current weather for a location"

  @Generable
  struct Arguments {
    @Guide(description: "City name")
    let city: String

    @Guide(description: "Temperature unit")
    let unit: String
  }

  @Generable
  struct Output {
    let temperature: Double
    let condition: String
    let humidity: Int
  }

  func call(arguments: Arguments) async throws -> Output {
    return Output(
      temperature: 22.5,
      condition: "sunny",
      humidity: 65
    )
  }
}

let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = AgentSession(
  model: model,
  tools: [WeatherTool()],
  instructions: "You are a helpful assistant.",
)

let response = try await session.run(to: "What's the weather like in San Francisco?")

print(response.content)
```

> [!NOTE]
> `LanguageModelSession` and `AgentSession` both take tools as an array, for example `tools: [WeatherTool(), OtherTool()]`. `LanguageModelSession` exposes tool calls for app-managed loops; `AgentSession` executes registered local tools automatically.

#### Recoverable Tool Rejections

If a tool call fails in a way the agent can correct (such as an unknown identifier or other validation issue), throw a `ToolRunRejection`. SwiftAgent forwards the structured content you provide to the model without aborting the loop so the agent can adjust its next action.

SwiftAgent always wraps your payload in a standardized envelope that includes `error: true` and the `reason` string so the agent can reliably detect recoverable rejections.

For quick cases, attach string-keyed details with the convenience initializer:

```swift
struct CustomerLookupTool: Tool {
  func call(arguments: Arguments) async throws -> Output {
    guard let customer = try await directory.loadCustomer(id: arguments.customerId) else {
      throw ToolRunRejection(
        reason: "Customer not found",
        details: [
          "issue": "customerNotFound",
          "customerId": arguments.customerId
        ]
      )
    }

    return Output(summary: customer.summary)
  }
}
```

For richer payloads, pass any `@Generable` type via the `content:` initializer to return structured data:

```swift
@Generable
struct CustomerLookupRejectionDetails {
  var issue: String
  var customerId: String
  var suggestions: [String]
}

throw ToolRunRejection(
  reason: "Customer not found",
  content: CustomerLookupRejectionDetails(
    issue: "customerNotFound",
    customerId: arguments.customerId,
    suggestions: ["Ask the user to confirm the identifier"]
  )
)
```

### Structured Responses

You can force the response to be structured by defining a `@Generable` type and passing it to the `session.respond` method:

```swift
import SwiftAgent

@Generable
struct WeatherReport {
  let temperature: Double
  let condition: String
  let humidity: Int
}

let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = LanguageModelSession(
  model: model,
  tools: [WeatherTool()],
  instructions: "You are a helpful assistant.",
)

let response = try await session.respond(
  to: Prompt("What's the weather like in San Francisco?"),
  generating: WeatherReport.self,
)

// Fully typed response content
print(response.content.temperature)
print(response.content.condition)
print(response.content.humidity)
```

The response body is now a fully typed `WeatherReport`. SwiftAgent validates the payload against your schema, so you can use the data immediately in UI or unit tests without defensive decoding.

### Access Transcripts

Every `LanguageModelSession` maintains a running transcript that records instructions, prompts, reasoning steps, tool calls, tool outputs, and responses. Iterate over it to drive custom analytics, persistence, or UI updates:

```swift
import SwiftAgent

let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = LanguageModelSession(
  model: model,
  instructions: "You are a helpful assistant.",
)

for entry in session.transcript {
  switch entry {
  case let .instructions(instructions):
    print("Instructions: ", instructions)
  case let .prompt(prompt):
    print("Prompt: ", prompt)
  case let .reasoning(reasoning):
    print("Reasoning: ", reasoning)
  case let .toolCalls(toolCalls):
    print("Tool Calls: ", toolCalls)
  case let .toolOutput(toolOutput):
    print("Tool Output: ", toolOutput)
  case let .response(response):
    print("Response: ", response)
  }
}
```

> [!NOTE]
> `LanguageModelSession` is `@Observable`, so SwiftUI and other Observation-based UI can track `isResponding`, `transcript`, `tokenUsage`, and provider metadata directly. The session remains thread-safe by publishing Observation changes around its internal locked state instead of exposing mutable transcript storage.

### Access Token Usage

Track each session's cumulative token consumption to budget response costs or surface usage in settings screens:

```swift
import SwiftAgent

let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = LanguageModelSession(
  model: model,
  instructions: "You are a helpful assistant.",
)

let response = try await session.respond(to: "What's the weather like in San Francisco?")

print(response.tokenUsage?.inputTokens ?? 0)
print(response.tokenUsage?.outputTokens ?? 0)
print(response.tokenUsage?.reasoningTokens ?? 0)
print(response.tokenUsage?.totalTokens ?? 0)
print(session.tokenUsage?.totalTokens ?? 0)
```

> Note: Each individual response also includes token usage information on `LanguageModelSession.Response`.

### Prompt Builder

Build rich prompts inline with the `Prompt` builder DSL. Tags group related context, keep instructions readable, and mirror the structure providers expect when you want to mix prose with metadata.

```swift
let response = try await session.respond(to: Prompt {
  "You are a friendly assistant who double-checks calculations."

  PromptTag("user-question") {
    "Explain how Swift's structured concurrency works."
  }

  PromptTag("formatting") {
    "Answer in three concise bullet points."
  }
})

print(response.content)
```

Under the hood SwiftAgent converts the builder result into the exact wire format required by the provider, so you can focus on intent instead of string concatenation.

### Custom Generation Options

You can specify generation options for your responses:

```swift
import SwiftAgent

let model = OpenAILanguageModel(apiKey: "sk-...", model: "gpt-5", apiVariant: .responses)
let session = LanguageModelSession(
  model: model,
  instructions: "You are a helpful assistant.",
)

var options = GenerationOptions(
  temperature: 0.7,
  maximumResponseTokens: 1_000,
)
options[custom: OpenAILanguageModel.self] = .init(
  reasoning: .init(effort: .low, summary: "auto"),
  serviceTier: .auto,
)

let response = try await session.respond(
  to: "What's the weather like in San Francisco?",
  options: options,
)

print(response.content)
```

These overrides apply only to the current turn, so you can increase creativity or token limits for specific prompts without mutating the session-wide configuration.

Anthropic uses its own generation options:

```swift
import SwiftAgent

let model = AnthropicLanguageModel(apiKey: "sk-ant-...", model: "claude-sonnet-4-5")
let session = LanguageModelSession(
  model: model,
  instructions: "You are a helpful assistant.",
)

var options = GenerationOptions(maximumResponseTokens: 1_000)
options[custom: AnthropicLanguageModel.self] = .init(thinking: .init(budgetTokens: 1_024))

let response = try await session.respond(
  to: "What's the weather like in San Francisco?",
  options: options,
)

print(response.content)
```

## Session Schema

Raw transcripts expose every event as `GeneratedContent`, which is flexible but awkward when you want to build UI or assertions.

Create a schema using `@SessionSchema` to describe the tools, groundings, and structured outputs you expect. `LanguageModelSession` remains the runtime; the schema is the typed layer you use to resolve transcript entries into strongly typed cases that mirror your declarations.

```swift
struct WeatherReportOutput: StructuredOutput {
  static let name = "weatherReport"

  @Generable
  struct Schema {
    let temperature: Double
    let condition: String
    let humidity: Int
  }
}

@SessionSchema
struct SessionSchema {
  @Tool var weatherTool = WeatherTool()
  @Tool var calculatorTool = CalculatorTool()

  @Grounding(Date.self) var currentDate
  @Grounding(VectorSearchResult.self) var searchResults

  @StructuredOutput(WeatherReportOutput.self) var weatherReport
  @StructuredOutput(CalculatorOutput.self) var calculatorOutput
}

let sessionSchema = SessionSchema()
let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = AgentSession(
  model: model,
  schema: sessionSchema,
  instructions: "You are a helpful assistant.",
)
```

Each macro refines a portion of the transcript:

- `@Tool` links a tool implementation to its decoded entries, giving you typed arguments, outputs, and errors for every invocation.
- `@Grounding` registers values you inject into prompts (like dates or search results) so they can be replayed alongside the prompt text.
- `@StructuredOutput` binds a guided generation schema to its decoded result, including partial streaming updates and final values.

### Tools

Decoded tool runs combine the model's argument payload and your tool's output in one place. That makes it easy to render progress UIs and surface recoverable errors without manually joining separate transcript entries.

```swift
import SwiftAgent

@SessionSchema
struct SessionSchema {
  @Tool var weatherTool = WeatherTool()
}

let sessionSchema = SessionSchema()
let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = AgentSession(
  model: model,
  schema: sessionSchema,
  instructions: "You are a helpful assistant.",
)

// let response = try await session.run(to: "What's the weather like in San Francisco?")
// ...

for entry in try sessionSchema.resolve(session.transcript) {
  switch entry {
  case let .toolRun(toolRun):
    switch toolRun {
    case let .weatherTool(weatherToolRun):
      if let arguments = weatherToolRun.finalArguments {
        print(arguments.city, arguments.unit)
      }

      if let output = weatherToolRun.output {
        print(output.condition, output.humidity, output.temperature)
      }
    default:
      break
    }
  default: break
  }
}
```

### Structured Output Entries

When you request structured data, decoded responses slot those values directly into the schema you registered on the session. You can pull the result out of the live response or from the transcript later, depending on your workflow.

```swift
import SwiftAgent

@SessionSchema
struct SessionSchema {
  @Tool var weatherTool = WeatherTool()
  @StructuredOutput(WeatherReportOutput.self) var weatherReport
}

let sessionSchema = SessionSchema()
let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = LanguageModelSession(
  model: model,
  schema: sessionSchema,
  instructions: "You are a helpful assistant.",
)

let response = try await session.respond(
  to: Prompt("What's the weather like in San Francisco?"),
  generating: WeatherReportOutput.Schema.self,
)

print(response.content) // WeatherReportOutput.Schema object

// Access the structured output in the resolved transcript
for entry in try sessionSchema.resolve(session.transcript) {
  switch entry {
  case let .response(response):
    switch response.structuredSegments[0].content {
    case let .weatherReport(weatherReport):
      if let weatherReport = weatherReport.finalContent {
        print(weatherReport.condition, weatherReport.humidity, weatherReport.temperature)
      }
    case .unknown:
      print("Unknown output")
    }

  default: break
  }
}
```

### Groundings

Groundings capture extra context you feed the model—like the current time or search snippets—and keep it synchronized with the prompt text. That makes it straightforward to inspect what the model saw and to recreate prompts later for debugging.

```swift
import SwiftAgent

@SessionSchema
struct SessionSchema {
  @Tool var weatherTool = WeatherTool()
  @Grounding(Date.self) var currentDate
  @StructuredOutput(WeatherReportOutput.self) var weatherReport
}

let sessionSchema = SessionSchema()
let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = LanguageModelSession(
  model: model,
  schema: sessionSchema,
  instructions: "You are a helpful assistant.",
)

let response = try await session.respond(
  to: Prompt {
    PromptTag("context") {
      "The current date is \(Date())."
    }

    PromptTag("user-query") {
      "What's the weather like in San Francisco?"
    }
  },
)

print(response.content)

// Access the input prompt and its groundings separately in the transcript
for entry in try sessionSchema.resolve(session.transcript) {
  switch entry {
  case let .prompt(prompt):
    print(prompt.input) // User input

    // Grounding sources stored alongside the input prompt
    // If this prompt was produced by a schema-aware grounding API, sources decode here.
    for source in prompt.sources {
      switch source {
      case let .currentDate(date):
        print("Current date: \(date)")
      }
    }

    print(prompt.prompt) // Final prompt sent to the model
  default: break
  }
}
```

## Streaming Responses

`streamResponse` emits snapshots while the agent thinks, calls tools, and crafts the final answer. SwiftAgent generates `PartiallyGenerated` companions for every `@Generable` type, turning each property into an optional so tokens can land as soon as they are decoded. SwiftAgent surfaces those partial values directly, then swaps in the fully realized type once the model finalizes the turn.

```swift
import SwiftAgent

@SessionSchema
struct SessionSchema {
  @Tool var weatherTool = WeatherTool()
  @StructuredOutput(WeatherReportOutput.self) var weatherReport
}

let sessionSchema = SessionSchema()
let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = LanguageModelSession(
  model: model,
  schema: sessionSchema,
  instructions: "You are a helpful assistant.",
)

// Create a response
let stream = session.streamResponse(to: "What's the weather like in San Francisco?")

for try await snapshot in stream {
  // Once the agent is sending the final response, the snapshot's content will start to populate
  if let content = snapshot.content {
    print(content)
  }

  // You can also access the generated transcript as it is streamed in
  print(snapshot.transcript)
}
```

Each snapshot contains the latest response fragment—if the model has started speaking—and the full transcript up to that point, giving you enough context to animate UI or log intermediate steps.

### Streaming Structured Outputs

Structured streaming works the same way: SwiftAgent first yields partially generated objects whose properties fill in as tokens arrive, then delivers the final schema once generation completes.

```swift
import SwiftAgent

@SessionSchema
struct SessionSchema {
  @Tool var weatherTool = WeatherTool()
  @StructuredOutput(WeatherReportOutput.self) var weatherReport
}

let sessionSchema = SessionSchema()
let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
let session = LanguageModelSession(
  model: model,
  schema: sessionSchema,
  instructions: "You are a helpful assistant.",
)

// Create a response
let stream = session.streamResponse(
  to: Prompt("What's the weather like in San Francisco?"),
  generating: WeatherReportOutput.Schema.self,
)

for try await snapshot in stream {
  // Once the agent is sending the final response, the snapshot's content will start to populate
  if let weatherReport = snapshot.content {
    print(weatherReport.condition ?? "Not received yet")
    print(weatherReport.humidity ?? "Not received yet")
    print(weatherReport.temperature ?? "Not received yet")
  }

  // You can also access the generated transcript as it is streamed in
  let transcript = snapshot.transcript
  let resolvedTranscript = try sessionSchema.resolve(transcript)

  print(transcript, resolvedTranscript)
}


// You can also observe the transcript during streaming
for entry in try sessionSchema.resolve(session.transcript) {
  switch entry {
  case let .response(response):
    switch response.structuredSegments[0].content {
    case let .weatherReport(weatherReport):
      switch weatherReport.content {
      case let .partial(partialWeatherReport):
        print(partialWeatherReport) // Partially populated object
      case let .final(finalWeatherReport):
        print(finalWeatherReport) // Fully populated object
      default:
        break // Not yet available
      }
    case .unknown:
      print("Unknown output")
    }

  default: break
  }
}
```

## Streaming State Helpers

SwiftAgent keeps SwiftUI views stable by exposing current projections of in-flight data. For tool runs, `currentArguments` always returns the partially generated variant of your argument type alongside an `isFinal` flag, so the view does not need to branch on enum states. When you need the fully validated payload reach for `finalArguments`, and if you want to respond to streaming transitions you can switch over `argumentsPhase`.

```swift
struct WeatherToolRunView: View {
  let run: ToolRun<WeatherTool>

  var body: some View {
    // 1. UI-friendly projection that stays stable while streaming
    if let currentArguments = run.currentArguments {
      VStack(alignment: .leading, spacing: 4) {
        Text("City: \(currentArguments.city ?? "-")")
        Text("Unit: \(currentArguments.unit ?? "-")")

        if currentArguments.isFinal {
          Text("Arguments locked in").font(.caption).foregroundStyle(.secondary)
        }
      }
      .monospacedDigit()
    }

    // 2. Fully validated payload, available once the model finalizes arguments
    if let finalArguments = run.finalArguments {
      Text("Resolved location: \(finalArguments.city)")
        .font(.footnote)
    }

    // 3. Underlying phase enum if you need to branch on streaming progress
    switch run.argumentsPhase {
    case let .partial(partialArguments):
      Text("Awaiting completion… \(partialArguments.city ?? "-")")
        .font(.caption)
        .foregroundStyle(.secondary)
    case let .final(finalArguments):
      Text("Final: \(finalArguments.city)")
        .font(.caption)
        .foregroundStyle(.green)
    case .none:
      EmptyView()
    }
  }
}
```

Structured outputs follow the same pattern with `snapshot.currentContent`: you always receive a partially generated projection that updates in place, while `finalContent` and `contentPhase` give you access to the completed schema and the streaming status respectively. The Example App’s Agent Playground view leans on these helpers to render incremental suggestions without triggering SwiftUI identity churn.

## Proxy Servers

Sending your OpenAI API key from the device is fine while sketching ideas, but it is not acceptable once you ship. Point the SDK at a proxy you control so the app never sees the provider credential:

```swift
let proxyToken = try await backend.issueTurnToken(for: userId)
let httpClient = URLSessionHTTPClient(configuration: .init(
  baseURL: URL(string: "https://api.your-backend.com/proxy/v1/")!,
  jsonEncoder: JSONEncoder(),
  jsonDecoder: JSONDecoder(),
  interceptors: HTTPClientInterceptors(
    prepareRequest: { request in
      request.setValue("Bearer \(proxyToken)", forHTTPHeaderField: "Authorization")
    }
  )
))
let model = OpenResponsesLanguageModel(
  apiKey: proxyToken,
  model: "openai/gpt-5",
  httpClient: httpClient
)
let session = LanguageModelSession(
  model: model,
  instructions: "You are a helpful assistant.",
)
```

SwiftAgent reuses the base URL you provide and appends the normal Responses API route, for example `https://api.your-backend.com/proxy/v1/responses`. Your backend should forward that path to OpenAI, attach its secret API key, and return the upstream response. In practice a robust proxy will:

- Validate the catch-all path so only the expected `/v1/responses` endpoint is reachable.
- Decode and inspect the body before relaying it (for example, enforce a `safety_identifier`, limit models, or reject obviously abusive payloads).
- Stream the request to OpenAI and pass the response straight through, optionally recording token usage for billing.

Every request emitted by the SDK already matches the Responses API schema, so the proxy does not need to reshape payloads.

### Per-turn Authorization

Protect the proxy with short-lived tokens instead of static API keys. Before each call to `respond` or `streamResponse`, ask your backend for a token that identifies the signed-in user and expires after one turn:

```swift
let turnToken = try await backend.issueTurnToken(for: userId)
let model = OpenResponsesLanguageModel(
  apiKey: turnToken,
  model: "openai/gpt-5",
  httpClient: proxyHTTPClient(for: turnToken)
)
let session = LanguageModelSession(model: model)
let response = try await session.respond(to: "Summarize yesterday's sales numbers.")
```

Install the turn token in the request headers used by your proxy HTTP client so every internal request for the turn inherits the same authorization.

For quick prototypes you can still pass an API key directly to `OpenResponsesLanguageModel` or `OpenAILanguageModel`, but remove direct provider credentials before release.

## Simulated Session

You can test and develop your agents without making API calls using the built-in simulation system. This is perfect for prototyping, testing, and developing UIs before integrating with live APIs.

```swift
import SwiftAgent
import SimulatedSession

// Create mockable tool wrappers
struct WeatherToolMock: MockableTool {
  var tool: WeatherTool

  func mockArguments() -> WeatherTool.Arguments {
    .init(city: "San Fransico", unit: "Celsius")
  }

  func mockOutput() async throws -> WeatherTool.Output {
    .init(
      temperature: 22.5,
      condition: "sunny",
      humidity: 65
    )
  }
}

@SessionSchema
struct SessionSchema {
  @Tool var weatherTool = WeatherTool()
}

let sessionSchema = SessionSchema()
let configuration = SimulationConfiguration(defaultGenerations: [
  .reasoning(summary: "Simulated Reasoning"),
  .toolRun(tool: WeatherToolMock(tool: WeatherTool())),
  .response(text: "It's a beautiful sunny day in San Francisco with 22.5°C!"),
])

let model = SimulationLanguageModel(configuration: configuration)
let session = LanguageModelSession(
  model: model,
  schema: sessionSchema,
  instructions: "You are a helpful assistant."
)

let response = try await session.respond(to: "What's the weather like in San Francisco?")

print(response.content) // "It's a beautiful sunny day in San Francisco with 22.5°C!"
```

## Logging

```swift
// Enable comprehensive logging
SwiftAgentConfiguration.setLoggingEnabled(true)

// Enable full request/response network logging (very verbose but helpful for debugging)
SwiftAgentConfiguration.setNetworkLoggingEnabled(true)

// Logs show:
// 🟢 Agent start — model=gpt-5 | tools=weather, calculator
// 🛠️ Tool call — weather [abc123]
// 📤 Tool output — weather [abc123]
// ✅ Finished
```

## Recording HTTP Fixtures

When writing unit tests, it’s often useful to capture real provider payloads and replay them locally.
SwiftAgent includes an opt-in recorder (`HTTPReplayRecorder`) that attaches to the SDK’s networking layer
via `HTTPClientInterceptors` and prints paste-ready Swift fixtures.

This is especially useful for streaming responses where you want to replay the full `text/event-stream`
payload in tests (like the ones using `ReplayHTTPClient` in this repository).

### Option 1: `AgentRecorder` CLI (recommended)

This repository includes a small macOS command-line tool (`AgentRecorder`) that runs recording scenarios and prints
paste-ready Swift fixtures to stdout.

1) Set API keys (either in your shell or in Xcode scheme env vars):
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`

Alternatively, if you already have a local `Secrets.plist` (not committed) you can let the CLI read keys from it:
- Set `AGENT_RECORDER_SECRETS_PLIST` (or pass `--secrets-plist <path>`)
- Provide `OpenAI_API_Key_Debug` and/or `Anthropic_API_Key_Debug` keys inside that plist
  - Tip: if you place `Secrets.plist` in the repo root and run `AgentRecorder` from the repo root, it will be picked up automatically.

2) Run from Xcode:
- Open `SwiftAgent.xcworkspace`
- Select the `AgentRecorder` scheme
- Run (stdout/stderr show in Xcode’s Debug console)

3) Run from Terminal:

```bash
xcodebuild -workspace SwiftAgent.xcworkspace -scheme AgentRecorder -destination "platform=macOS" -derivedDataPath .tmp/DerivedData build
OPENAI_API_KEY=sk-... ./.tmp/DerivedData/Build/Products/Debug/AgentRecorder --list-scenarios
OPENAI_API_KEY=sk-... ./.tmp/DerivedData/Build/Products/Debug/AgentRecorder --provider openai --scenario openai/streaming-tool-calls/weather
```

### Option 2: Use the API directly

```swift
import SwiftAgent

let recorder = HTTPReplayRecorder(
  options: .init(
    includeRequests: false,
    includeHeaders: true,
    prettyPrintJSON: true
  )
)

var interceptors = HTTPClientInterceptors(
  prepareRequest: { request in
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
  }
)
interceptors = interceptors.recording(to: recorder)

let configuration = HTTPClientConfiguration(
  baseURL: URL(string: "https://api.openai.com/v1/")!,
  jsonEncoder: JSONEncoder(),
  jsonDecoder: JSONDecoder(),
  interceptors: interceptors
)

let httpClient = URLSessionHTTPClient(configuration: configuration)
let model = OpenResponsesLanguageModel(
  apiKey: apiKey,
  model: "openai/gpt-5",
  httpClient: httpClient
)
let session = LanguageModelSession(
  model: model,
  instructions: "You are a helpful assistant.",
)

_ = try await session.respond(to: "Hello!")

await recorder.printSwiftFixtureSnippet()
```

Notes:
- Streaming responses are recorded as raw `text/event-stream` payloads (may be partial if the consumer stops iterating early).
- Enabling stream capture buffers stream bytes in memory; keep it enabled only for debugging/fixture recording.
- Request headers may contain secrets; the recorder redacts common auth header fields before printing.

## Development Status

**Work in Progress**: SwiftAgent is under active development. APIs may change, and breaking updates are expected. Use in production with caution.

## Example App

SwiftAgent ships with a SwiftUI demo that showcases the SDK in action. Open the project at `Examples/Example App/ExampleApp` to explore an agent playground that:

- Configures OpenAI and Anthropic language models with the bundled `SessionSchema`, calculator tool, weather tool, and a structured weather report output.
- Streams responses while rendering prompts, reasoning summaries, tool runs, and final replies in a chat-style transcript UI.
- Demonstrates tool-specific views (calculator and weather) with live argument updates, results, and SwiftUI previews backed by `SimulationLanguageModel` scenarios.

Use the app to experiment with SwiftAgent locally or as a starting point for integrating the SDK into your own SwiftUI experience.

## License

SwiftAgent is available under the MIT license. See [LICENSE](LICENSE) for more information.

## Acknowledgments

- Inspired by Apple's [FoundationModels](https://developer.apple.com/documentation/foundationmodels) framework
- Built with the amazing Swift ecosystem and community

_Made with ❤️ for the Swift community_
