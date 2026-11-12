import Foundation
import Testing

@testable import DeskBar

struct PersistentAppOrderTests {
    @Test
    func newAppsAreAppendedAfterKnownOnes() {
        var order = PersistentAppOrder(appKeys: ["mail", "chat"])
        let added = order.register(["term", "chat", "web"])
        #expect(added)
        #expect(order.appKeys == ["mail", "chat", "term", "web"])
        let addedAgain = order.register(["mail"])
        #expect(addedAgain == false)
    }

    @Test
    func arrangedSortsByAppAndKeepsWindowsOfOneAppTogetherInPlace() {
        let order = PersistentAppOrder(appKeys: ["mail", "chat", "term"])
        let windows = [("term", 1), ("chat", 1), ("mail", 1), ("term", 2), ("unknown", 1), ("chat", 2)]

        let arranged = order.arranged(windows) { $0.0 }

        #expect(arranged.map { "\($0.0)\($0.1)" } == ["mail1", "chat1", "chat2", "term1", "term2", "unknown1"])
    }

    @Test
    func manualReorderKeepsSlotsOfAppsThatAreNotRunning() {
        // "chat" is closed. Dragging "term" before "mail" must not move "chat".
        var order = PersistentAppOrder(appKeys: ["mail", "chat", "term", "web"])

        order.applyManualOrder(["term", "mail", "web"])

        #expect(order.appKeys == ["term", "chat", "mail", "web"])
    }

    @Test
    func draggingTheLastWindowOfAnAppBehindAnotherMovesTheApp() {
        // [A1, A2, B1] with A2 dragged behind B1 gives [A1, B1, A2].
        var order = PersistentAppOrder(appKeys: ["A", "B"])

        order.applyManualOrder(["A", "B", "A"], movedIndex: 2)

        #expect(order.appKeys == ["B", "A"])
        #expect(order.arranged([("A", 1), ("B", 1), ("A", 2)]) { $0.0 }.map { "\($0.0)\($0.1)" } == ["B1", "A1", "A2"])
    }

    @Test
    func reorderingWindowsWithinAnAppKeepsTheAppOrder() {
        // [A1, A2, B1] with A1 dragged behind A2 gives [A2, A1, B1].
        var order = PersistentAppOrder(appKeys: ["A", "B"])

        order.applyManualOrder(["A", "A", "B"], movedIndex: 1)

        #expect(order.appKeys == ["A", "B"])
    }

    @Test
    func draggingAnAppForwardMovesItBeforeTheOthers() {
        // [A1, B1, B2] with B2 dragged before A1 gives [B2, A1, B1].
        var order = PersistentAppOrder(appKeys: ["A", "B"])

        order.applyManualOrder(["B", "A", "B"], movedIndex: 0)

        #expect(order.appKeys == ["B", "A"])
    }

    @Test
    func manualReorderCollapsesRepeatedAppsAndRegistersNewOnes() {
        var order = PersistentAppOrder(appKeys: ["mail", "term"])

        order.applyManualOrder(["term", "term", "new", "mail"])

        #expect(order.appKeys == ["term", "new", "mail"])
    }

    @Test
    func orderSurvivesARestartThroughTheSettings() {
        let suiteName = "PersistentAppOrderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = TaskbarSettings(defaults: defaults)
        #expect(settings.keepAppOrder == false)
        #expect(settings.persistentAppOrder.appKeys.isEmpty)

        settings.keepAppOrder = true
        settings.persistentAppOrder = PersistentAppOrder(appKeys: ["chat", "mail"])

        let reloaded = TaskbarSettings(defaults: defaults)
        #expect(reloaded.keepAppOrder)
        #expect(reloaded.persistentAppOrder.appKeys == ["chat", "mail"])
    }

    @Test
    func duplicateKeysFromStorageAreIgnored() {
        #expect(PersistentAppOrder(appKeys: ["a", "b", "a"]).appKeys == ["a", "b"])
    }
}
