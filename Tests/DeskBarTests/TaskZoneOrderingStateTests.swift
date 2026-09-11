import Foundation
import Testing

@testable import DeskBar

@Test
func taskOrderAppendsNewItemsToTheEndAndKeepsExistingPositions() {
    var state = TaskZoneOrderingState()
    state.reconcile(currentIDs: ["a", "b", "c"])
    #expect(state.arrangedIDs(for: ["c", "a", "b"]) == ["a", "b", "c"])

    state.reconcile(currentIDs: ["a", "b", "c", "d"])
    #expect(state.arrangedIDs(for: ["d", "b", "a", "c"]) == ["a", "b", "c", "d"])
}

@Test
func taskOrderRestoresItemThatVanishedForOnePass() {
    // The bug this guards: a Session Manager agent tab or a minimized window drops out for a
    // single refresh and comes back at the far right instead of where the user left it.
    var state = TaskZoneOrderingState()
    let start = Date()
    state.reconcile(currentIDs: ["a", "b", "c"], now: start)

    state.reconcile(currentIDs: ["b", "c"], now: start.addingTimeInterval(1))
    #expect(state.arrangedIDs(for: ["b", "c"]) == ["b", "c"])

    state.reconcile(currentIDs: ["a", "b", "c"], now: start.addingTimeInterval(2))
    #expect(state.arrangedIDs(for: ["a", "b", "c"]) == ["a", "b", "c"])
}

@Test
func taskOrderRestoresLeftmostItemAcrossAnIntervalWithANewWindow() {
    // "The leftmost tab stopped being leftmost after I opened a window."
    var state = TaskZoneOrderingState()
    let start = Date()
    state.reconcile(currentIDs: ["a", "b", "c"], now: start)

    // `a` blinks out at the same moment a new window `d` opens.
    state.reconcile(currentIDs: ["b", "c", "d"], now: start.addingTimeInterval(1))
    #expect(state.arrangedIDs(for: ["b", "c", "d"]) == ["b", "c", "d"])

    state.reconcile(currentIDs: ["a", "b", "c", "d"], now: start.addingTimeInterval(2))
    #expect(state.arrangedIDs(for: ["a", "b", "c", "d"]) == ["a", "b", "c", "d"])
}

@Test
func taskOrderForgetsItemsAbsentBeyondTheRetentionInterval() {
    var state = TaskZoneOrderingState()
    let start = Date()
    state.reconcile(currentIDs: ["a", "b", "c"], now: start)

    // The absence clock starts when absence is first observed, not when the window really went.
    state.reconcile(currentIDs: ["b", "c"], now: start.addingTimeInterval(1))
    #expect(state.orderedItemIDs == ["a", "b", "c"])

    let afterRetention = start.addingTimeInterval(TaskZoneOrderingState.itemRetentionInterval + 2)
    state.reconcile(currentIDs: ["b", "c"], now: afterRetention)
    #expect(state.orderedItemIDs == ["b", "c"])

    // A genuinely closed-and-reopened window is a new item and belongs at the end.
    state.reconcile(currentIDs: ["a", "b", "c"], now: afterRetention.addingTimeInterval(1))
    #expect(state.arrangedIDs(for: ["a", "b", "c"]) == ["b", "c", "a"])
}

@Test
func taskOrderCapsRetainedAbsentItems() {
    var state = TaskZoneOrderingState()
    let start = Date()
    let allItemIDs = (0..<(TaskZoneOrderingState.maximumRetainedAbsentItems + 20)).map { "item-\($0)" }
    state.reconcile(currentIDs: allItemIDs, now: start)

    state.reconcile(currentIDs: [], now: start.addingTimeInterval(1))
    #expect(state.orderedItemIDs.count == TaskZoneOrderingState.maximumRetainedAbsentItems)
}

@Test
func taskOrderKeepsManualOrderStableWhenWindowCountChanges() {
    // Ranks used to be stored as absolute indices and clamped to the item count, so a dragged
    // tab drifted left as windows closed and jumped right again as they opened.
    var state = TaskZoneOrderingState()
    state.reconcile(currentIDs: ["a", "b", "c", "d"])
    state.applyManualOrder(["d", "a", "b", "c"], userPositionedItemID: "d")
    #expect(state.arrangedIDs(for: ["a", "b", "c", "d"]) == ["d", "a", "b", "c"])

    state.reconcile(currentIDs: ["a", "d"])
    #expect(state.arrangedIDs(for: ["a", "d"]) == ["d", "a"])

    state.reconcile(currentIDs: ["a", "b", "c", "d", "e"])
    #expect(state.arrangedIDs(for: ["a", "b", "c", "d", "e"]) == ["d", "a", "b", "c", "e"])
}

@Test
func manualOrderKeepsAbsentItemsAnchoredToTheirPredecessor() {
    var state = TaskZoneOrderingState()
    let start = Date()
    state.reconcile(currentIDs: ["a", "b", "c", "d"], now: start)

    // `b` is temporarily absent while the user drags `d` to the front.
    state.reconcile(currentIDs: ["a", "c", "d"], now: start.addingTimeInterval(1))
    state.applyManualOrder(["d", "a", "c"], userPositionedItemID: "d")

    // `b` returns and lands back after `a`, where it was, not at the end.
    state.reconcile(currentIDs: ["a", "b", "c", "d"], now: start.addingTimeInterval(2))
    #expect(state.arrangedIDs(for: ["a", "b", "c", "d"]) == ["d", "a", "b", "c"])
}

@Test
func arrangedIDsAppendsUnreconciledItemsRatherThanDroppingThem() {
    var state = TaskZoneOrderingState()
    state.reconcile(currentIDs: ["a", "b"])

    #expect(state.arrangedIDs(for: ["a", "b", "surprise"]) == ["a", "b", "surprise"])
    #expect(state.arrangedIDs(for: []) == [])
}

@Test
func parkedMinimizedWindowKeepsItsSlotIndefinitely() {
    // A minimized window is deliberately absent from the task zone, so it must not be treated as
    // closed. Restoring it after a long park puts it back where it was, not at the end.
    var state = TaskZoneOrderingState()
    let start = Date()
    state.reconcile(currentIDs: ["a", "b", "c"], now: start)

    // `b` is minimized: gone from the rendered list, still known to WindowManager.
    let longAfterRetention = start.addingTimeInterval(
        TaskZoneOrderingState.itemRetentionInterval * 10
    )
    state.reconcile(currentIDs: ["a", "c"], knownIDs: ["a", "b", "c"], now: start.addingTimeInterval(1))
    state.reconcile(currentIDs: ["a", "c"], knownIDs: ["a", "b", "c"], now: longAfterRetention)
    #expect(state.arrangedIDs(for: ["a", "c"]) == ["a", "c"])

    state.reconcile(
        currentIDs: ["a", "b", "c"],
        knownIDs: ["a", "b", "c"],
        now: longAfterRetention.addingTimeInterval(1)
    )
    #expect(state.arrangedIDs(for: ["a", "b", "c"]) == ["a", "b", "c"])
}

@Test
func parkedWindowStillExpiresOnceItIsNoLongerKnown() {
    // Closing a window while it is minimized must eventually release its slot.
    var state = TaskZoneOrderingState()
    let start = Date()
    state.reconcile(currentIDs: ["a", "b", "c"], now: start)
    state.reconcile(currentIDs: ["a", "c"], knownIDs: ["a", "b", "c"], now: start.addingTimeInterval(1))

    // `b` is gone for good — no longer reported as known.
    let afterClose = start.addingTimeInterval(2)
    state.reconcile(currentIDs: ["a", "c"], knownIDs: ["a", "c"], now: afterClose)
    #expect(state.orderedItemIDs == ["a", "b", "c"])

    let afterRetention = afterClose.addingTimeInterval(
        TaskZoneOrderingState.itemRetentionInterval + 1
    )
    state.reconcile(currentIDs: ["a", "c"], knownIDs: ["a", "c"], now: afterRetention)
    #expect(state.orderedItemIDs == ["a", "c"])
}
