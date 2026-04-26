import Foundation

final class Locked<State> {
  private let lock = NSLock()
  private var state: State

  init(_ state: State) {
    self.state = state
  }

  func withLock<Value>(_ body: (inout State) throws -> Value) rethrows -> Value {
    try lock.withLock {
      try body(&state)
    }
  }
}

extension Locked: @unchecked Sendable where State: Sendable {}
