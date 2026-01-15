// By Dennis Müller

import AnthropicSession
import Darwin
import Foundation
import FoundationModels
import OpenAI
import OpenAISession
import SwiftAgent
import SwiftAnthropic

@main
struct AgentRecorderCLI {
  static func main() async {
    SwiftAgentConfiguration.setLoggingEnabled(false)
    SwiftAgentConfiguration.setNetworkLoggingEnabled(false)

    do {
      let options = try Options.parse(CommandLine.arguments)

      if options.showHelp {
        print(Options.helpText)
        return
      }

      if options.listScenarios {
        print(Scenario.helpText)
        return
      }

      try await run(options: options)
    } catch {
      Stderr.print("error: \(error.localizedDescription)")
      Stderr.print("")
      Stderr.print(Options.helpText)
      exit(1)
    }
  }

  private static func run(options: Options) async throws {
    let recorder = HTTPReplayRecorder(
      options: .init(
        includeRequests: options.includeRequests,
        includeHeaders: options.includeHeaders,
        prettyPrintJSON: options.prettyPrintJSON,
      ),
    )

    if let scenario = options.scenario {
      try await scenario.run(with: recorder)
      await print(recorder.swiftFixtureSnippet())
      return
    }

    switch options.provider {
    case .openAI:
      try await Scenario.toolCallWeatherOpenAI.run(with: recorder)
      await print(recorder.swiftFixtureSnippet())
    case .anthropic:
      try await Scenario.toolCallWeatherAnthropic.run(with: recorder)
      await print(recorder.swiftFixtureSnippet())
    case .both:
      try await Scenario.toolCallWeatherOpenAI.run(with: recorder)
      await print(recorder.swiftFixtureSnippet(responseNamePrefix: "openAIResponse"))

      await recorder.reset()

      try await Scenario.toolCallWeatherAnthropic.run(with: recorder)
      print("")
      await print(recorder.swiftFixtureSnippet(responseNamePrefix: "anthropicResponse"))
    }
  }
}

private enum Provider: String {
  case openAI = "openai"
  case anthropic
  case both
}

private struct Options {
  var provider: Provider = .both
  var scenario: Scenario?
  var includeRequests: Bool = false
  var includeHeaders: Bool = true
  var prettyPrintJSON: Bool = true

  var showHelp: Bool = false
  var listScenarios: Bool = false

  static func parse(_ argv: [String]) throws -> Options {
    var options = Options()

    var iterator = argv.dropFirst().makeIterator()
    while let arg = iterator.next() {
      switch arg {
      case "--help", "-h":
        options.showHelp = true
      case "--list-scenarios":
        options.listScenarios = true
      case "--provider":
        let value = iterator.next() ?? ""
        guard let provider = Provider(rawValue: value.lowercased()) else {
          throw CLIError.invalidArgument("--provider \(value)")
        }

        options.provider = provider
      case "--scenario":
        let value = iterator.next() ?? ""
        guard let scenario = Scenario(rawValue: value.lowercased()) else {
          throw CLIError.invalidArgument("--scenario \(value)")
        }

        options.scenario = scenario
      case "--include-requests":
        options.includeRequests = true
      case "--include-headers":
        options.includeHeaders = true
      case "--no-include-headers":
        options.includeHeaders = false
      case "--pretty-print-json":
        options.prettyPrintJSON = true
      case "--no-pretty-print-json":
        options.prettyPrintJSON = false
      default:
        throw CLIError.invalidArgument(arg)
      }
    }

    return options
  }

  static let helpText: String = """
  AgentRecorder — record real provider HTTP responses and print paste-ready Swift fixtures.

  Usage:
    AgentRecorder [--provider openai|anthropic|both] [--scenario <name>] [--include-requests] [--no-include-headers] [--no-pretty-print-json]
    AgentRecorder --list-scenarios
    AgentRecorder --help

  Environment:
    OPENAI_API_KEY       Required for --provider openai|both
    ANTHROPIC_API_KEY    Required for --provider anthropic|both

  Output:
    Prints Swift raw-string fixtures to stdout. (Xcode: appears in the Debug console.)
  """
}

private enum Scenario: String, CaseIterable {
  case toolCallWeatherOpenAI = "tool-call-weather-openai"
  case toolCallWeatherAnthropic = "tool-call-weather-anthropic"

  static let helpText: String = """
  Scenarios:
    \(Scenario.toolCallWeatherOpenAI.rawValue)
    \(Scenario.toolCallWeatherAnthropic.rawValue)
  """

  func run(with recorder: HTTPReplayRecorder) async throws {
    switch self {
    case .toolCallWeatherOpenAI:
      try await runOpenAI(recorder: recorder)
    case .toolCallWeatherAnthropic:
      try await runAnthropic(recorder: recorder)
    }
  }

  private func runOpenAI(recorder: HTTPReplayRecorder) async throws {
    let apiKey = try Environment.required("OPENAI_API_KEY")

    let configuration = OpenAIConfiguration.recording(
      apiKey: apiKey,
      recorder: recorder,
    )

    let session = OpenAISession(
      tools: OpenAIWeatherTool(),
      instructions: "Always call `get_weather` exactly once before answering.",
      configuration: configuration,
    )

    let prompt = "What is the weather in New York City, USA?"
    let stream = try session.streamResponse(
      to: prompt,
      options: .init(include: [.reasoning_encryptedContent]),
    )

    for try await _ in stream {}
  }

  private func runAnthropic(recorder: HTTPReplayRecorder) async throws {
    let apiKey = try Environment.required("ANTHROPIC_API_KEY")

    let configuration = AnthropicConfiguration.recording(
      apiKey: apiKey,
      recorder: recorder,
    )

    let session = AnthropicSession(
      tools: AnthropicWeatherTool(),
      instructions: "Always call `get_weather` exactly once before answering. Reply with \"Done.\" after tool output.",
      configuration: configuration,
    )

    let stream = try session.streamResponse(
      to: "What's the weather in Tokyo on 2026-01-15 in the afternoon?",
      using: .claude37SonnetLatest,
    )

    for try await _ in stream {}
  }
}

private struct OpenAIWeatherTool: FoundationModels.Tool {
  var name: String = "get_weather"
  var description: String = "Get current weather for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}

private struct AnthropicWeatherTool: FoundationModels.Tool {
  var name: String = "get_weather"
  var description: String = "Get current weather for a given location."

  @Generable
  struct Arguments {
    var location: String
    var requestedDate: String
    var timeOfDay: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}

private enum Environment {
  static func required(_ key: String) throws -> String {
    let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value, value.isEmpty == false else {
      throw CLIError.missingEnvironmentVariable(key)
    }

    return value
  }
}

private enum Stderr {
  static func print(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}

private enum CLIError: LocalizedError {
  case missingEnvironmentVariable(String)
  case invalidArgument(String)

  var errorDescription: String? {
    switch self {
    case let .missingEnvironmentVariable(key):
      "Missing required environment variable: \(key)"
    case let .invalidArgument(argument):
      "Invalid argument: \(argument)"
    }
  }
}

private extension OpenAIConfiguration {
  static func recording(
    apiKey: String,
    recorder: HTTPReplayRecorder,
  ) -> OpenAIConfiguration {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    let decoder = JSONDecoder()

    var interceptors = HTTPClientInterceptors(
      prepareRequest: { request in
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      },
      onUnauthorized: { _, _, _ in
        false
      },
    )
    interceptors = interceptors.recording(to: recorder)

    let configuration = HTTPClientConfiguration(
      baseURL: URL(string: "https://api.openai.com")!,
      defaultHeaders: [:],
      timeout: 60,
      jsonEncoder: encoder,
      jsonDecoder: decoder,
      interceptors: interceptors,
    )

    return OpenAIConfiguration(httpClient: URLSessionHTTPClient(configuration: configuration))
  }
}

private extension AnthropicConfiguration {
  static func recording(
    apiKey: String,
    apiVersion: String = "2023-06-01",
    recorder: HTTPReplayRecorder,
  ) -> AnthropicConfiguration {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let defaultHeaders: [String: String] = [
      "anthropic-version": apiVersion,
    ]

    var interceptors = HTTPClientInterceptors(
      prepareRequest: { request in
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
      },
      onUnauthorized: { _, _, _ in
        false
      },
    )
    interceptors = interceptors.recording(to: recorder)

    let configuration = HTTPClientConfiguration(
      baseURL: URL(string: "https://api.anthropic.com")!,
      defaultHeaders: defaultHeaders,
      timeout: 60,
      jsonEncoder: encoder,
      jsonDecoder: decoder,
      interceptors: interceptors,
    )

    return AnthropicConfiguration(httpClient: URLSessionHTTPClient(configuration: configuration))
  }
}
