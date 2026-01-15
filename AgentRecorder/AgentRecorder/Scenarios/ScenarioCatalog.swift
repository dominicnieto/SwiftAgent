// By Dennis Müller

enum ScenarioCatalog {
  static let defaultOpenAIScenario: AgentRecorderScenario = OpenAIStreamingToolCallsWeatherScenario.scenario
  static let defaultAnthropicScenario: AgentRecorderScenario = AnthropicStreamingToolCallsWeatherScenario.scenario

  static let all: [AgentRecorderScenario] = [
    // Anthropic
    AnthropicTextScenario.scenario,
    AnthropicStreamingTextScenario.scenario,
    AnthropicStreamingThinkingScenario.scenario,
    AnthropicStructuredOutputScenario.scenario,
    AnthropicStreamingToolCallsWeatherScenario.scenario,
    AnthropicStreamingToolCallsNoArgsPingScenario.scenario,

    // OpenAI
    OpenAITextScenario.scenario,
    OpenAIStreamingTextScenario.scenario,
    OpenAIStreamingStructuredOutputScenario.scenario,
    OpenAIStructuredOutputScenario.scenario,
    OpenAIToolCallsWeatherScenario.scenario,
    OpenAIStreamingToolCallsMultipleScenario.scenario,
    OpenAIStreamingToolCallsWeatherScenario.scenario,
  ]

  static func requireScenario(
    id: String,
  ) throws -> AgentRecorderScenario {
    let normalized = id.lowercased()
    guard let scenario = all.first(where: { $0.id == normalized }) else {
      throw AgentRecorderError.unknownScenario(id)
    }

    return scenario
  }

  static let helpText: String = {
    var lines: [String] = []

    lines.append("Scenarios:")
    lines.append("")

    let anthropic = all.filter { $0.provider == .anthropic }
    if anthropic.isEmpty == false {
      lines.append("  Anthropic:")
      for scenario in anthropic {
        lines.append("    \(scenario.id)  →  \(scenario.unitTestFile)")
      }
      lines.append("")
    }

    let openAI = all.filter { $0.provider == .openAI }
    if openAI.isEmpty == false {
      lines.append("  OpenAI:")
      for scenario in openAI {
        lines.append("    \(scenario.id)  →  \(scenario.unitTestFile)")
      }
      lines.append("")
    }

    return lines.joined(separator: "\n")
  }()
}
