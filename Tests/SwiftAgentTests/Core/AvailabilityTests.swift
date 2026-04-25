import Testing

@testable import SwiftAgent

@Suite("Availability")
struct AvailabilityTests {
    @Test func availableComparesEqual() {
        let first = Availability<String>.available
        let second = Availability<String>.available

        #expect(first == second)
    }

    @Test func unavailablePreservesReason() {
        let availability = Availability<String>.unavailable("network offline")

        guard case .unavailable(let reason) = availability else {
            Issue.record("Expected unavailable state")
            return
        }

        #expect(reason == "network offline")
    }

    @Test func hashableAvailabilityCanBeStoredInSet() {
        let values: Set<Availability<String>> = [
            .available,
            .unavailable("missing credentials"),
            .unavailable("missing credentials"),
        ]

        #expect(values.count == 2)
    }

    @Test func sendableAvailabilityCanCrossTaskBoundary() async {
        let availability = Availability<String>.unavailable("rate limited")

        let result = await Task {
            availability
        }.value

        #expect(result == .unavailable("rate limited"))
    }
}
