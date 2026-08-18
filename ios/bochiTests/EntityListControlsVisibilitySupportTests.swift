import CoreGraphics
import Testing
@testable import bochi

struct EntityListControlsVisibilitySupportTests {
    // Behaviour: controls should stay available while the user is still close
    // to the top of the list, even if the first movement is downward.
    @Test("Near top always keeps controls visible")
    func nearTopAlwaysKeepsControlsVisible() {
        var state = EntityListControlsVisibilityState(isVisible: false)

        let isVisible = state.update(
            contentOffsetY: EntityListControlsVisibilityState.nearTopDistance - 1,
            contentTopInset: 0,
            timestamp: 1
        )

        #expect(isVisible == true)
    }

    // Behaviour: a deliberate downward scroll should move the controls away so
    // list rows get the full reading surface.
    @Test("Fast downward scroll hides controls")
    func fastDownwardScrollHidesControls() {
        var state = EntityListControlsVisibilityState()

        _ = state.update(contentOffsetY: 80, contentTopInset: 0, timestamp: 1)
        let isVisible = state.update(contentOffsetY: 190, contentTopInset: 0, timestamp: 1.2)

        #expect(isVisible == false)
    }

    // Behaviour: once the user is just past the top safe zone, a fast downward
    // scroll should make room for list rows instead of keeping controls pinned.
    @Test("Fast downward scroll just below top hides controls")
    func fastDownwardScrollJustBelowTopHidesControls() {
        var state = EntityListControlsVisibilityState()

        _ = state.update(
            contentOffsetY: EntityListControlsVisibilityState.nearTopDistance + 1,
            contentTopInset: 0,
            timestamp: 1
        )
        let isVisible = state.update(
            contentOffsetY: EntityListControlsVisibilityState.nearTopDistance + 131,
            contentTopInset: 0,
            timestamp: 1.2
        )

        #expect(isVisible == false)
    }

    // Behaviour: a tiny downward flick should not hide controls even if that
    // short movement is fast enough to clear the speed threshold.
    @Test("Fast short downward scroll keeps controls visible")
    func fastShortDownwardScrollKeepsControlsVisible() {
        var state = EntityListControlsVisibilityState()

        _ = state.update(contentOffsetY: 80, contentTopInset: 0, timestamp: 1)
        let isVisible = state.update(contentOffsetY: 130, contentTopInset: 0, timestamp: 1.05)

        #expect(isVisible == true)
    }

    // Behaviour: if the user pauses after a partial downward scroll, the next
    // downward gesture should need the full travel distance again.
    @Test("Paused downward scroll resets travel distance")
    func pausedDownwardScrollResetsTravelDistance() {
        var state = EntityListControlsVisibilityState()

        _ = state.update(contentOffsetY: 80, contentTopInset: 0, timestamp: 1)
        _ = state.update(contentOffsetY: 140, contentTopInset: 0, timestamp: 1.05)
        _ = state.update(contentOffsetY: 150, contentTopInset: 0, timestamp: 1.5)
        let isVisible = state.update(contentOffsetY: 200, contentTopInset: 0, timestamp: 1.6)

        #expect(isVisible == true)
    }

    // Behaviour: slowly reading downward should not remove the controls just
    // because the list drifted by a small amount.
    @Test("Slow downward scroll keeps controls visible")
    func slowDownwardScrollKeepsControlsVisible() {
        var state = EntityListControlsVisibilityState()

        _ = state.update(contentOffsetY: 80, contentTopInset: 0, timestamp: 1)
        let isVisible = state.update(contentOffsetY: 88, contentTopInset: 0, timestamp: 1.5)

        #expect(isVisible == true)
    }

    // Behaviour: a deliberate upward scroll should bring controls back, using
    // the same velocity threshold that hides them on downward scroll.
    @Test("Fast upward scroll shows controls")
    func fastUpwardScrollShowsControls() {
        var state = EntityListControlsVisibilityState(isVisible: false)

        _ = state.update(contentOffsetY: 220, contentTopInset: 0, timestamp: 1)
        let isVisible = state.update(contentOffsetY: 110, contentTopInset: 0, timestamp: 1.2)

        #expect(isVisible == true)
    }

    // Behaviour: a tiny upward flick should not reopen controls even if that
    // short movement is fast enough to clear the speed threshold.
    @Test("Fast short upward scroll keeps controls hidden")
    func fastShortUpwardScrollKeepsControlsHidden() {
        var state = EntityListControlsVisibilityState(isVisible: false)

        _ = state.update(contentOffsetY: 140, contentTopInset: 0, timestamp: 1)
        let isVisible = state.update(contentOffsetY: 90, contentTopInset: 0, timestamp: 1.05)

        #expect(isVisible == false)
    }

    // Behaviour: if the user pauses after a partial upward scroll, the next
    // upward gesture should need the full travel distance again.
    @Test("Paused upward scroll resets travel distance")
    func pausedUpwardScrollResetsTravelDistance() {
        var state = EntityListControlsVisibilityState(isVisible: false)

        _ = state.update(contentOffsetY: 220, contentTopInset: 0, timestamp: 1)
        _ = state.update(contentOffsetY: 160, contentTopInset: 0, timestamp: 1.05)
        _ = state.update(contentOffsetY: 150, contentTopInset: 0, timestamp: 1.5)
        let isVisible = state.update(contentOffsetY: 100, contentTopInset: 0, timestamp: 1.6)

        #expect(isVisible == false)
    }

    // Behaviour: a slow upward drift while reading should not immediately
    // reopen the controls after the user intentionally hid them.
    @Test("Slow upward scroll keeps controls hidden")
    func slowUpwardScrollKeepsControlsHidden() {
        var state = EntityListControlsVisibilityState(isVisible: false)

        _ = state.update(contentOffsetY: 140, contentTopInset: 0, timestamp: 1)
        let isVisible = state.update(contentOffsetY: 132, contentTopInset: 0, timestamp: 1.5)

        #expect(isVisible == false)
    }

    // Behaviour: when the list rubber-bands past the bottom, the automatic
    // bounce back upward should not be treated as the user asking for controls.
    @Test("Bottom bounce recovery keeps controls hidden")
    func bottomBounceRecoveryKeepsControlsHidden() {
        var state = EntityListControlsVisibilityState(isVisible: false)

        _ = state.update(
            contentOffsetY: 1030,
            contentTopInset: 0,
            contentBottomLimitY: 1000,
            timestamp: 1
        )
        let isVisible = state.update(
            contentOffsetY: 1000,
            contentTopInset: 0,
            contentBottomLimitY: 1000,
            timestamp: 1.1
        )

        #expect(isVisible == false)
    }

    // Behaviour: iOS can settle a bottom rubber-band with a second tiny upward
    // rebound; that should still not reopen the controls.
    @Test("Second tiny bottom rebound keeps controls hidden")
    func secondTinyBottomReboundKeepsControlsHidden() {
        var state = EntityListControlsVisibilityState(isVisible: false)

        _ = state.update(contentOffsetY: 1030, contentTopInset: 0, contentBottomLimitY: 1000, timestamp: 1)
        _ = state.update(contentOffsetY: 1000, contentTopInset: 0, contentBottomLimitY: 1000, timestamp: 1.1)
        let isVisible = state.update(contentOffsetY: 996, contentTopInset: 0, contentBottomLimitY: 1000, timestamp: 1.2)

        #expect(isVisible == false)
    }

    // Behaviour: once the user genuinely scrolls up away from the bottom, the
    // controls should return instead of staying suppressed by the bounce guard.
    @Test("Real upward scroll away from bottom shows controls")
    func realUpwardScrollAwayFromBottomShowsControls() {
        var state = EntityListControlsVisibilityState(isVisible: false)

        _ = state.update(contentOffsetY: 1030, contentTopInset: 0, contentBottomLimitY: 1000, timestamp: 1)
        _ = state.update(contentOffsetY: 1000, contentTopInset: 0, contentBottomLimitY: 1000, timestamp: 1.1)
        _ = state.update(contentOffsetY: 996, contentTopInset: 0, contentBottomLimitY: 1000, timestamp: 1.2)
        let isVisible = state.update(contentOffsetY: 860, contentTopInset: 0, contentBottomLimitY: 1000, timestamp: 1.35)

        #expect(isVisible == true)
    }
}
