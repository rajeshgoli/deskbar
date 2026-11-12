import Foundation

/// A per-app order for the task zone that survives restarts and absences.
///
/// `TaskZoneOrderingState` remembers positions per window and forgets an item
/// 45 seconds after it disappears, so an app that is closed and reopened, or
/// any app after a restart, lands at the end again. With "Keep apps in a
/// fixed order" on, items are additionally sorted by their app's rank here:
/// every app keeps the slot it was last dragged to, and an app never seen
/// before is appended after the known ones.
struct PersistentAppOrder: Equatable {
    static let defaultsKey = "persistentAppOrder"

    private(set) var appKeys: [String]

    init(appKeys: [String] = []) {
        var seen = Set<String>()
        self.appKeys = appKeys.filter { seen.insert($0).inserted }
    }

    init(defaults: UserDefaults) {
        self.init(appKeys: defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    func save(to defaults: UserDefaults) {
        defaults.set(appKeys, forKey: Self.defaultsKey)
    }

    /// Appends apps not seen before, in the order given. Returns whether anything was added.
    @discardableResult
    mutating func register(_ keys: [String]) -> Bool {
        var known = Set(appKeys)
        let added = keys.filter { known.insert($0).inserted }
        appKeys.append(contentsOf: added)
        return !added.isEmpty
    }

    /// Sorts `items` by their app's rank. Items of the same app, and items of
    /// unregistered apps, keep their relative order.
    func arranged<Item>(_ items: [Item], appKey: (Item) -> String) -> [Item] {
        let rankByKey = Dictionary(uniqueKeysWithValues: appKeys.enumerated().map { ($1, $0) })
        return items.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rankByKey[appKey(lhs.element)] ?? Int.max
                let rhsRank = rankByKey[appKey(rhs.element)] ?? Int.max
                return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
            }
            .map(\.element)
    }

    /// Records a manual reorder. `keysInDisplayOrder` lists the app of every
    /// visible item after the drag; the visible apps take that relative order
    /// within the slots they already occupied, so apps that are not running
    /// keep their place.
    ///
    /// `movedIndex` is the position the dragged item landed at. Its app is
    /// placed there, wherever that app's other items are: dragging the last
    /// window of A behind B moves A behind B, rather than A staying first
    /// because its other windows still come before B.
    mutating func applyManualOrder(_ keysInDisplayOrder: [String], movedIndex: Int? = nil) {
        let movedKey = movedIndex.flatMap { keysInDisplayOrder.indices.contains($0) ? keysInDisplayOrder[$0] : nil }
        var seen = Set<String>()
        var visibleKeys: [String] = []
        for (index, key) in keysInDisplayOrder.enumerated() {
            if key == movedKey, index != movedIndex {
                continue
            }
            if seen.insert(key).inserted {
                visibleKeys.append(key)
            }
        }
        register(visibleKeys)

        var nextVisibleKey = visibleKeys.makeIterator()
        appKeys = appKeys.map { key in
            seen.contains(key) ? (nextVisibleKey.next() ?? key) : key
        }
    }
}
