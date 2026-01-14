// By Dennis Müller

import OpenAISession
import SwiftUI

@main
struct ExampleApp: App {
  init() {
    // Enable logging for development
    SwiftAgentConfiguration.setLoggingEnabled(true)
    SwiftAgentConfiguration.setNetworkLoggingEnabled(false)
  }

  var body: some Scene {
    WindowGroup {
      TabView {
        AgentPlaygroundView()
          .tabItem {
            Label("OpenAI", systemImage: "sparkles")
          }
        AnthropicPlaygroundView()
          .tabItem {
            Label("Anthropic", systemImage: "a.circle")
          }
      }
    }
  }
}
