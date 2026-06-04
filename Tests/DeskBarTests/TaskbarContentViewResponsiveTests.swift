import CoreGraphics
import Testing
@testable import DeskBar

@Test
func compactOuterInsetsApplyOnNarrowFullWidthBars() {
    #expect(
        TaskbarContentView.shouldUseCompactOuterInsets(
            contentWidth: TaskbarContentView.compactOuterInsetContentWidthThreshold,
            usesAdaptiveTaskLayout: false
        )
    )
}

@Test
func taskZoneEdgeSpacersHideOnNarrowFullWidthBars() {
    #expect(
        TaskbarContentView.shouldShowTaskZoneEdgeSpacers(
            contentWidth: TaskbarContentView.compactOuterInsetContentWidthThreshold,
            usesAdaptiveTaskLayout: false
        ) == false
    )
}

@Test
func taskZoneEdgeSpacersRemainOnUltrawideWhenContentFits() {
    #expect(
        TaskbarContentView.shouldShowTaskZoneEdgeSpacers(
            contentWidth: TaskbarContentView.compactOuterInsetContentWidthThreshold + 1,
            usesAdaptiveTaskLayout: false
        )
    )
}

@Test
func taskZoneEdgeSpacersHideOnOverflowAtAnyWidth() {
    #expect(
        TaskbarContentView.shouldShowTaskZoneEdgeSpacers(
            contentWidth: TaskbarContentView.compactOuterInsetContentWidthThreshold + 1000,
            usesAdaptiveTaskLayout: true
        ) == false
    )
}

@Test
func compactOuterInsetsDoNotChangeUltrawideWhenContentFits() {
    #expect(
        TaskbarContentView.shouldUseCompactOuterInsets(
            contentWidth: TaskbarContentView.compactOuterInsetContentWidthThreshold + 1,
            usesAdaptiveTaskLayout: false
        ) == false
    )
}

@Test
func compactOuterInsetsApplyOnOverflowAtAnyWidth() {
    #expect(
        TaskbarContentView.shouldUseCompactOuterInsets(
            contentWidth: TaskbarContentView.compactOuterInsetContentWidthThreshold + 1000,
            usesAdaptiveTaskLayout: true
        )
    )
}

@Test
func layoutBudgetKeepsFullWidthWhenRegularInsetsAreVisible() {
    #expect(
        TaskbarContentView.layoutBudgetContentWidth(
            contentWidth: 3000,
            usesCompactOuterInsets: false
        ) == 3000
    )
}

@Test
func layoutBudgetLeavesTinyTrailingGuardWhenCompactInsetsAreVisible() {
    #expect(
        TaskbarContentView.layoutBudgetContentWidth(
            contentWidth: 1512,
            usesCompactOuterInsets: true
        ) == CGFloat(1512) - TaskbarContentView.compactTrailingOverflowGuardWidth
    )
}
