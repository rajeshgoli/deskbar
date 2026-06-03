import CoreGraphics

struct TaskbarWidthPlanItem: Equatable {
    let preferredWidth: CGFloat
    let minimumWidth: CGFloat

    init(preferredWidth: CGFloat, minimumWidth: CGFloat) {
        self.minimumWidth = max(0, minimumWidth)
        self.preferredWidth = max(self.minimumWidth, preferredWidth)
    }
}

enum TaskbarWidthPlanner {
    static func uniformWidthCap(
        availableWidth: CGFloat,
        fixedWidth: CGFloat,
        items: [TaskbarWidthPlanItem]
    ) -> CGFloat? {
        guard !items.isEmpty else {
            return nil
        }

        let availableItemWidth = max(0, availableWidth - fixedWidth)
        let preferredItemWidth = totalWidth(for: items, cap: nil)
        guard preferredItemWidth > availableItemWidth + 0.5 else {
            return nil
        }

        let largestMinimumWidth = items.map(\.minimumWidth).max() ?? 0
        let minimumItemWidth = items.reduce(0) { $0 + $1.minimumWidth }
        guard availableItemWidth > minimumItemWidth else {
            return largestMinimumWidth
        }

        var low = largestMinimumWidth
        var high = items.map(\.preferredWidth).max() ?? largestMinimumWidth

        for _ in 0..<32 {
            let midpoint = (low + high) / 2
            let width = totalWidth(for: items, cap: midpoint)

            if width > availableItemWidth {
                high = midpoint
            } else {
                low = midpoint
            }
        }

        return max(largestMinimumWidth, floor(low + 0.001))
    }

    private static func totalWidth(for items: [TaskbarWidthPlanItem], cap: CGFloat?) -> CGFloat {
        items.reduce(0) { total, item in
            let width: CGFloat
            if let cap {
                width = min(item.preferredWidth, max(item.minimumWidth, cap))
            } else {
                width = item.preferredWidth
            }

            return total + width
        }
    }
}

func approximatelyEqual(_ lhs: CGFloat?, _ rhs: CGFloat?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
        return true
    case (.some(let lhs), .some(let rhs)):
        return abs(lhs - rhs) < 0.5
    case (.none, .some), (.some, .none):
        return false
    }
}
