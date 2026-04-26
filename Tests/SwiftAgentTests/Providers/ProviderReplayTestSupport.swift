import Foundation

@testable import SwiftAgent

@Generable
struct ProviderReplayForecast {
  var summary: String
  var temperatureCelsius: Int
}

@Generable
struct ProviderReplayPerson {
  var name: String
  var age: Int
  var email: String?
}

struct WeatherTool: Tool {
  var name: String { "get_weather" }
  var description: String { "Returns weather for a city." }

  @Generable
  struct Arguments {
    var city: String
  }

  func call(arguments: Arguments) async throws -> String {
    "Sunny in \(arguments.city)"
  }
}
