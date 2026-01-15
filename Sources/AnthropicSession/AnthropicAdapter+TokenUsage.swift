// By Dennis Müller

import SwiftAgent
@preconcurrency import SwiftAnthropic

extension AnthropicAdapter {
  func transcriptStatus(
    from stopReason: String?,
  ) -> Transcript.Status {
    switch stopReason {
    case "max_tokens":
      .incomplete
    default:
      .completed
    }
  }

  func tokenUsage(
    from response: MessageResponse,
  ) -> TokenUsage? {
    tokenUsage(from: response.usage)
  }

  func tokenUsage(
    from usage: MessageResponse.Usage,
  ) -> TokenUsage? {
    let inputTokens = usage.inputTokens
    let outputTokens = usage.outputTokens
    let totalTokens = inputTokens.map { $0 + outputTokens }

    return TokenUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
      cachedTokens: usage.cacheReadInputTokens,
      reasoningTokens: usage.thinkingTokens,
    )
  }
}
