import CoreGraphics
import Testing
@testable import DeskBar

struct TaskbarWidthPlannerTests {
    @Test
    func noCapWhenPreferredWidthsFit() {
        let cap = TaskbarWidthPlanner.uniformWidthCap(
            availableWidth: 520,
            fixedWidth: 80,
            items: [
                TaskbarWidthPlanItem(preferredWidth: 160, minimumWidth: 56),
                TaskbarWidthPlanItem(preferredWidth: 200, minimumWidth: 56)
            ]
        )

        #expect(cap == nil)
    }

    @Test
    func capsUniformlyWhenButtonsNeedToShrink() {
        let cap = TaskbarWidthPlanner.uniformWidthCap(
            availableWidth: 500,
            fixedWidth: 140,
            items: [
                TaskbarWidthPlanItem(preferredWidth: 200, minimumWidth: 56),
                TaskbarWidthPlanItem(preferredWidth: 200, minimumWidth: 56),
                TaskbarWidthPlanItem(preferredWidth: 200, minimumWidth: 56)
            ]
        )

        #expect(cap == 120)
    }

    @Test
    func leavesNaturallySmallButtonsBelowCap() {
        let cap = TaskbarWidthPlanner.uniformWidthCap(
            availableWidth: 250,
            fixedWidth: 0,
            items: [
                TaskbarWidthPlanItem(preferredWidth: 80, minimumWidth: 56),
                TaskbarWidthPlanItem(preferredWidth: 200, minimumWidth: 56),
                TaskbarWidthPlanItem(preferredWidth: 200, minimumWidth: 56)
            ]
        )

        #expect(cap == 85)
    }

    @Test
    func fallsBackToLargestMinimumWhenMinimumsCannotFit() {
        let cap = TaskbarWidthPlanner.uniformWidthCap(
            availableWidth: 120,
            fixedWidth: 0,
            items: [
                TaskbarWidthPlanItem(preferredWidth: 200, minimumWidth: 56),
                TaskbarWidthPlanItem(preferredWidth: 340, minimumWidth: 88)
            ]
        )

        #expect(cap == 88)
    }
}
