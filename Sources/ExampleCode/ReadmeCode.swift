// By Dennis Muller

import Foundation
import SwiftAgent

@MainActor
public enum ReadmeCode {
  @SessionSchema
  struct SessionSchema {
    @Tool var weatherTool = WeatherTool()
    @Grounding(Date.self) var currentDate
    @StructuredOutput(WeatherReportOutput.self) var weatherReport
  }

  /// Step: Basic Usage
  func basicUsage() async throws {
    let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
    let session = LanguageModelSession(
      model: model,
      instructions: "You are a helpful assistant.",
    )

    let response = try await session.respond(to: "What's the weather like in San Francisco?")

    print(response.content)
  }

  /// Step: Basic Usage (Anthropic)
  func basicUsageAnthropic() async throws {
    let model = AnthropicLanguageModel(apiKey: "sk-ant-...", model: "claude-sonnet-4-5")
    let session = LanguageModelSession(
      model: model,
      instructions: "You are a helpful assistant.",
    )

    let response = try await session.respond(to: "What's the weather like in San Francisco?")

    print(response.content)
  }

  /// Step: Building Tools
  func buildingTools() async throws {
    let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
    let session = LanguageModelSession(
      model: model,
      tools: [WeatherTool()],
      instructions: "You are a helpful assistant.",
    )

    let response = try await session.respond(to: "What's the weather like in San Francisco?")

    print(response.content)
  }

  func structuredOutputs() async throws {
    let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
    let session = LanguageModelSession(
      model: model,
      tools: [WeatherTool()],
      instructions: "Return accurate weather reports.",
    )

    let response = try await session.respond(
      to: Prompt("What's the weather like in San Francisco?"),
      generating: WeatherReport.self,
    )

    print(response.content.temperature)
    print(response.content.condition)
    print(response.content.humidity)
  }

  func sessionSchemaToolResolution() async throws {
    let schema = SessionSchema()
    let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
    let session = LanguageModelSession(
      model: model,
      tools: [schema.weatherTool],
      instructions: "You are a helpful assistant.",
    )

    _ = try await session.respond(to: "What's the weather like in San Francisco?")

    for entry in try schema.resolve(session.transcript) {
      guard case let .toolRun(toolRun) = entry else {
        continue
      }

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
    }
  }

  func sessionSchemaStructuredOutputResolution() async throws {
    let schema = SessionSchema()
    let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
    let session = LanguageModelSession(
      model: model,
      instructions: "Return accurate weather reports.",
    )

    let response = try await session.respond(
      to: Prompt("What's the weather like in San Francisco?"),
      generating: WeatherReportOutput.Schema.self,
    )

    print(response.content.condition)

    for entry in try schema.resolve(session.transcript) {
      guard case let .response(response) = entry else {
        continue
      }

      for segment in response.structuredSegments {
        switch segment.content {
        case let .weatherReport(report):
          if let report = report.finalContent {
            print(report.condition, report.humidity, report.temperature)
          }
        case .unknown:
          break
        }
      }
    }
  }

  func accessTranscripts() async throws {
    let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
    let session = LanguageModelSession(
      model: model,
      instructions: "You are a helpful assistant.",
    )

    _ = try await session.respond(to: "What's the weather like in San Francisco?")

    for entry in session.transcript {
      switch entry {
      case let .instructions(instructions):
        print("Instructions:", instructions)
      case let .prompt(prompt):
        print("Prompt:", prompt)
      case let .reasoning(reasoning):
        print("Reasoning:", reasoning)
      case let .toolCalls(toolCalls):
        print("Tool Calls:", toolCalls)
      case let .toolOutput(toolOutput):
        print("Tool Output:", toolOutput)
      case let .response(response):
        print("Response:", response)
      }
    }
  }

  func accessUsageAndMetadata() async throws {
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
    print(response.responseMetadata?.providerName ?? "unknown")
    print(response.responseMetadata?.modelID ?? "unknown")
  }

  func customGenerationOptions() async throws {
    let model = OpenAILanguageModel(apiKey: "sk-...", model: "gpt-5", apiVariant: .responses)
    let session = LanguageModelSession(
      model: model,
      instructions: "You are a concise weather assistant.",
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
  }

  func customGenerationOptionsAnthropic() async throws {
    let model = AnthropicLanguageModel(apiKey: "sk-ant-...", model: "claude-sonnet-4-5")
    let session = LanguageModelSession(
      model: model,
      instructions: "You are a concise weather assistant.",
    )

    var options = GenerationOptions(maximumResponseTokens: 1_000)
    options[custom: AnthropicLanguageModel.self] = .init(
      thinking: .init(budgetTokens: 1_024),
    )

    let response = try await session.respond(
      to: "What's the weather like in San Francisco?",
      options: options,
    )

    print(response.content)
  }

  func promptBuilder() async throws {
    let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
    let session = LanguageModelSession(
      model: model,
      instructions: "Use the supplied context before answering.",
    )

    let response = try await session.respond(to: Prompt {
      PromptTag("context") {
        "The current date is \(Date())."
      }

      PromptTag("user-query") {
        "What's the weather like in San Francisco?"
      }
    })

    print(response.content)
  }

  func streamingResponses() async throws {
    let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
    let session = LanguageModelSession(
      model: model,
      tools: [WeatherTool()],
      instructions: "You are a helpful assistant.",
    )

    let stream = session.streamResponse(to: "What's the weather like in San Francisco?")

    for try await snapshot in stream {
      if let content = snapshot.content {
        print(content)
      }

      if let metadata = snapshot.responseMetadata {
        print(metadata.providerName ?? "unknown")
      }

      print(snapshot.transcript)
    }
  }

  func streamingStructuredOutputs() async throws {
    let model = OpenResponsesLanguageModel(apiKey: "sk-...", model: "openai/gpt-5")
    let session = LanguageModelSession(
      model: model,
      instructions: "Return accurate weather reports.",
    )

    let stream = session.streamResponse(
      to: Prompt("What's the weather like in San Francisco?"),
      generating: WeatherReport.self,
    )

    for try await snapshot in stream {
      if let weatherReport = snapshot.content {
        print(weatherReport.condition ?? "Not received yet")
        print(weatherReport.humidity ?? 0)
        print(weatherReport.temperature ?? 0)
      }

      print(snapshot.transcript)
    }
  }
}

extension ReadmeCode {
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
      Output(
        temperature: 22.5,
        condition: "sunny",
        humidity: 65,
      )
    }
  }

  @Generable
  struct WeatherReport {
    let temperature: Double
    let condition: String
    let humidity: Int
  }

  struct WeatherReportOutput: StructuredOutput {
    static let name = "weatherReport"

    @Generable
    struct Schema {
      let temperature: Double
      let condition: String
      let humidity: Int
    }
  }
}
