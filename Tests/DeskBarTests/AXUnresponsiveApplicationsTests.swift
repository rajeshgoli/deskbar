import ApplicationServices
import Foundation
import Testing
@testable import DeskBar

@Test
func unresponsiveApplicationIsSkippedOnlyDuringCooldown() {
    let tracker = AXUnresponsiveApplications(cooldown: 1)
    let start = Date(timeIntervalSinceReferenceDate: 0)

    tracker.record(.cannotComplete, for: 42, now: start)

    #expect(tracker.shouldSkip(42, now: start.addingTimeInterval(0.5)))
    #expect(!tracker.shouldSkip(7, now: start.addingTimeInterval(0.5)))
    #expect(!tracker.shouldSkip(42, now: start.addingTimeInterval(1)))
}

@Test
func answeredRequestClearsUnresponsiveApplication() {
    let tracker = AXUnresponsiveApplications(cooldown: 1)
    let start = Date(timeIntervalSinceReferenceDate: 0)

    tracker.record(.cannotComplete, for: 42, now: start)
    tracker.record(.success, for: 42, now: start)

    #expect(!tracker.shouldSkip(42, now: start))
}

@Test
func lastingAccessibilityFailureDoesNotStartCooldown() {
    let tracker = AXUnresponsiveApplications(cooldown: 1)
    let start = Date(timeIntervalSinceReferenceDate: 0)

    tracker.record(.apiDisabled, for: 42, now: start)

    #expect(!tracker.shouldSkip(42, now: start))
}
