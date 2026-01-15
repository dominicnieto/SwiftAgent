// By Dennis Müller

import Foundation

struct AgentRecorderSecrets: Sendable {
  var secretsPlistPath: String?

  init(secretsPlistPath: String?) {
    self.secretsPlistPath = secretsPlistPath
  }

  func openAIAPIKey() throws -> String {
    try apiKey(
      environmentKey: "OPENAI_API_KEY",
      secretsPlistKey: "OpenAI_API_Key_Debug",
    )
  }

  func anthropicAPIKey() throws -> String {
    try apiKey(
      environmentKey: "ANTHROPIC_API_KEY",
      secretsPlistKey: "Anthropic_API_Key_Debug",
    )
  }

  private func apiKey(
    environmentKey: String,
    secretsPlistKey: String,
  ) throws -> String {
    if let envValue = Environment.value(environmentKey), envValue.isEmpty == false {
      return envValue
    }

    guard let resolvedPlistURL = resolveSecretsPlistURL() else {
      throw AgentRecorderError.missingAPIKey(
        environmentKey: environmentKey,
        secretsPlistKey: secretsPlistKey,
      )
    }
    guard let plistValue = loadPlistValue(url: resolvedPlistURL, key: secretsPlistKey) else {
      throw AgentRecorderError.missingAPIKey(
        environmentKey: environmentKey,
        secretsPlistKey: secretsPlistKey,
      )
    }

    if plistValue.isEmpty {
      throw AgentRecorderError.missingAPIKey(
        environmentKey: environmentKey,
        secretsPlistKey: secretsPlistKey,
      )
    }

    return plistValue
  }

  private func resolveSecretsPlistURL() -> URL? {
    if let overridePath = secretsPlistPath {
      let url = urlFromUserPath(overridePath)
      if FileManager.default.fileExists(atPath: url.path) {
        return url
      }
    }

    if let envPath = Environment.value("AGENT_RECORDER_SECRETS_PLIST"), envPath.isEmpty == false {
      let url = urlFromUserPath(envPath)
      if FileManager.default.fileExists(atPath: url.path) {
        return url
      }
    }

    let defaultURL = urlFromUserPath("Secrets.plist")
    if FileManager.default.fileExists(atPath: defaultURL.path) {
      return defaultURL
    }

    let legacyURL = urlFromUserPath("Examples/Example App/ExampleApp/Secrets.plist")
    if FileManager.default.fileExists(atPath: legacyURL.path) {
      return legacyURL
    }

    return nil
  }

  private func urlFromUserPath(_ path: String) -> URL {
    if path.hasPrefix("/") {
      return URL(fileURLWithPath: path)
    }

    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return base.appendingPathComponent(path)
  }

  private func loadPlistValue(url: URL, key: String) -> String? {
    do {
      let data = try Data(contentsOf: url)
      let plist = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil,
      )

      guard let dict = plist as? [String: Any] else {
        return nil
      }

      let value = dict[key] as? String
      return value?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      return nil
    }
  }
}
