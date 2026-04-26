/// A decision about how to handle a tool call emitted by a language model.
public enum ToolExecutionDecision: Sendable {
  /// Execute the tool call using the associated tool.
  case execute

  /// Stop the session after tool calls are generated without executing them.
  case stop

  /// Provide tool output without executing the tool.
  ///
  /// Use this to supply results from an external system or cached responses.
  case provideOutput([Transcript.Segment])
}

/// Policy controls for session-owned tool execution.
public struct ToolExecutionPolicy: Sendable, Equatable {
  /// Behavior when the model calls a tool that is not registered with the session.
  public enum MissingToolBehavior: Sendable, Equatable {
    /// Record a tool-output entry explaining that the tool is unavailable.
    case recordErrorOutput
    /// Throw an error and stop the turn.
    case throwError
  }

  /// Behavior when a registered tool throws.
  public enum FailureBehavior: Sendable, Equatable {
    /// Throw a ``LanguageModelSession/ToolCallError`` and stop the turn.
    case throwError
    /// Record the thrown error as tool output and continue.
    case recordErrorOutput
  }

  /// Retry behavior for registered tools that throw.
  public enum RetryPolicy: Sendable, Equatable {
    /// Do not retry failed tool calls.
    case none
    /// Retry non-cancellation errors up to the total attempt count.
    case retryNonCancellationErrors(maxAttempts: Int)

    var maximumAttempts: Int {
      switch self {
      case .none:
        1
      case .retryNonCancellationErrors(let maxAttempts):
        max(1, maxAttempts)
      }
    }
  }

  /// Whether independent tool calls may execute concurrently.
  public var allowsParallelExecution: Bool

  /// How registered tool failures are retried.
  public var retryPolicy: RetryPolicy

  /// How missing tool calls are handled.
  public var missingToolBehavior: MissingToolBehavior

  /// How tool execution failures are handled.
  public var failureBehavior: FailureBehavior

  /// Creates a tool execution policy.
  public init(
    allowsParallelExecution: Bool = true,
    retryPolicy: RetryPolicy = .none,
    missingToolBehavior: MissingToolBehavior = .recordErrorOutput,
    failureBehavior: FailureBehavior = .throwError,
  ) {
    self.allowsParallelExecution = allowsParallelExecution
    self.retryPolicy = retryPolicy
    self.missingToolBehavior = missingToolBehavior
    self.failureBehavior = failureBehavior
  }

  /// Default agent behavior: execute tools, report missing tools to the model, and throw on failures.
  public static var automatic: ToolExecutionPolicy {
    ToolExecutionPolicy()
  }
}

/// A delegate that observes and controls tool execution for a session.
public protocol ToolExecutionDelegate: Sendable {
  /// Notifies the delegate when the model generates tool calls.
  ///
  /// - Parameters:
  ///   - toolCalls: The tool calls produced by the model.
  ///   - session: The session that generated the tool calls.
  func didGenerateToolCalls(_ toolCalls: [Transcript.ToolCall], in session: LanguageModelSession) async

  /// Asks the delegate how to handle a tool call.
  ///
  /// Return `.execute` to run the tool, `.stop` to halt after tool calls are generated,
  /// or `.provideOutput` to supply output without executing the tool.
  /// - Parameters:
  ///   - toolCall: The tool call to evaluate.
  ///   - session: The session requesting the decision.
  func toolCallDecision(
    for toolCall: Transcript.ToolCall,
    in session: LanguageModelSession,
  ) async -> ToolExecutionDecision

  /// Notifies the delegate after a tool call produces output.
  ///
  /// - Parameters:
  ///   - toolCall: The tool call that was handled.
  ///   - output: The output sent back to the model.
  ///   - session: The session that executed the tool call.
  func didExecuteToolCall(
    _ toolCall: Transcript.ToolCall,
    output: Transcript.ToolOutput,
    in session: LanguageModelSession,
  ) async

  /// Notifies the delegate when a tool call fails.
  ///
  /// - Parameters:
  ///   - toolCall: The tool call that failed.
  ///   - error: The underlying error raised during execution.
  ///   - session: The session that attempted the tool call.
  func didFailToolCall(
    _ toolCall: Transcript.ToolCall,
    error: any Error,
    in session: LanguageModelSession,
  ) async
}

// MARK: - Default Implementations

public extension ToolExecutionDelegate {
  /// Provides a default no-op implementation.
  func didGenerateToolCalls(_ toolCalls: [Transcript.ToolCall], in session: LanguageModelSession) async {
    _ = toolCalls
    _ = session
  }

  /// Provides a default decision that executes the tool call.
  func toolCallDecision(
    for toolCall: Transcript.ToolCall,
    in session: LanguageModelSession,
  ) async -> ToolExecutionDecision {
    _ = toolCall
    _ = session
    return .execute
  }

  /// Provides a default no-op implementation.
  func didExecuteToolCall(
    _ toolCall: Transcript.ToolCall,
    output: Transcript.ToolOutput,
    in session: LanguageModelSession,
  ) async {
    _ = toolCall
    _ = output
    _ = session
  }

  /// Provides a default no-op implementation.
  func didFailToolCall(
    _ toolCall: Transcript.ToolCall,
    error: any Error,
    in session: LanguageModelSession,
  ) async {
    _ = toolCall
    _ = error
    _ = session
  }
}
