// By Dennis Müller

import Foundation
import SwiftAgent

public struct SimulationGenerationOptions: CustomGenerationOptions {
  public enum SimulationGenerationOptionsError: Error, LocalizedError, Sendable {
    case noGenerationsAvailable

    public var errorDescription: String? {
      "No simulated generations are available for this simulation run."
    }
  }

  public var minimumStreamingSnapshotInterval: Duration?
  public var simulatedGenerations: [SimulatedGeneration]
  public var tokenUsageOverride: TokenUsage?

  public init(
    simulatedGenerations: [SimulatedGeneration] = [],
    minimumStreamingSnapshotInterval: Duration? = nil,
    tokenUsageOverride: TokenUsage? = nil,
  ) {
    self.simulatedGenerations = simulatedGenerations
    self.minimumStreamingSnapshotInterval = minimumStreamingSnapshotInterval
    self.tokenUsageOverride = tokenUsageOverride
  }

  public init() {
    self.init(simulatedGenerations: [])
  }

  public static func == (lhs: SimulationGenerationOptions, rhs: SimulationGenerationOptions) -> Bool {
    lhs.minimumStreamingSnapshotInterval == rhs.minimumStreamingSnapshotInterval
      && lhs.tokenUsageOverride == rhs.tokenUsageOverride
      && lhs.simulatedGenerations.map(\.testDescription) == rhs.simulatedGenerations.map(\.testDescription)
  }
}

private extension SimulatedGeneration {
  var testDescription: String {
    switch self {
    case let .reasoning(summary):
      "reasoning:\(summary)"
    case let .toolRun(tool):
      "tool:\(tool.tool.name)"
    case let .textResponse(text):
      "text:\(text)"
    case let .structuredResponse(content):
      "structured:\(content.stableJsonString)"
    }
  }
}
