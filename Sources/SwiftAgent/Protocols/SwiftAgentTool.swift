// By Dennis Müller

import Foundation

/// A thin wrapper around SwiftAgent's local ``Tool`` protocol that constrains its arguments and output to
/// `Generable` types.
///
/// - Note: You do not conform to this protocol directly. When you define a language model session and pass a `@Tool`
/// property, the macro will synthesize a conformance to this protocol.
public protocol SwiftAgentTool: SwiftAgent.Tool where Arguments: Generable, Output: Generable {}
