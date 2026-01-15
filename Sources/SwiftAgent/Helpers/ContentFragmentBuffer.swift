// By Dennis Müller

/// A small helper for assembling indexed streaming fragments.
///
/// Providers often stream multiple "content blocks" in parallel, keyed by an index. This buffer
/// ensures writes are safe for sparse indices while preserving order.
package struct ContentFragmentBuffer: Sendable {
  package private(set) var fragments: [String]

  package init() {
    fragments = []
  }

  package mutating func append(
    _ text: String,
    at index: Int,
  ) {
    ensureCapacity(for: index)
    fragments[index].append(text)
  }

  package mutating func assign(
    _ text: String,
    at index: Int,
  ) {
    ensureCapacity(for: index)
    fragments[index] = text
  }

  package func joined(
    separator: String = "",
  ) -> String {
    fragments.joined(separator: separator)
  }

  package var nonEmptyFragments: [String] {
    fragments.filter { !$0.isEmpty }
  }

  private mutating func ensureCapacity(
    for index: Int,
  ) {
    if fragments.count <= index {
      fragments.append(contentsOf: Array(repeating: "", count: index - fragments.count + 1))
    }
  }
}
