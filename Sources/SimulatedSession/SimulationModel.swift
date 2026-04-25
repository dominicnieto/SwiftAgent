// By Dennis Müller

import Foundation
import OpenAI
import OSLog
import SwiftAgent

/// The model to use for generating a response.
public enum SimulationModel: Equatable, Hashable, Sendable, AdapterModel {
  case simulated
  public static let `default`: SimulationModel = .simulated
}
