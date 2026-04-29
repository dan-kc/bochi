import Foundation
import Testing
@testable import tofustash

@MainActor
struct ToastManagerTests {

    private func makeSUT() -> ToastManager {
        return ToastManager()
    }

    // MARK: - Showing toasts

    // Behaviour: When a new habit is discarded, a toast notification appears
    // giving the user a chance to recover their work.
    @Test func showingToastAddsItToActiveToasts() {
        let sut = makeSUT()
        sut.show(message: "Habit Discarded", actionLabel: "Recover") {}
        #expect(sut.toasts.count == 1)
        #expect(sut.toasts[0].message == "Habit Discarded")
    }

    // Behaviour: The toast shows a visible countdown so the user knows
    // how long they have to recover their discarded habit.
    @Test func newToastStartsWithFullDuration() {
        let sut = makeSUT()
        sut.show(message: "Test", actionLabel: "Recover", duration: 5) {}
        #expect(sut.remainingSeconds[sut.toasts[0].id] == 5)
    }

    // MARK: - Dismissing toasts

    // Behaviour: When the user swipes a toast away, it is removed immediately
    // so it no longer takes up screen space.
    @Test func dismissRemovesToastFromActiveList() {
        let sut = makeSUT()
        sut.show(message: "Test", actionLabel: "Recover") {}
        let id = sut.toasts[0].id
        sut.dismiss(id)
        #expect(sut.toasts.isEmpty)
    }

    // Behaviour: Dismissing a toast also cleans up its countdown state
    // so there are no stale timers left behind.
    @Test func dismissCleansUpRemainingSeconds() {
        let sut = makeSUT()
        sut.show(message: "Test", actionLabel: "Recover") {}
        let id = sut.toasts[0].id
        sut.dismiss(id)
        #expect(sut.remainingSeconds[id] == nil)
    }

    // MARK: - Recovering (performing action)

    // Behaviour: When the user taps "Recover" on a toast, the discarded
    // habit form is restored and the toast is dismissed.
    @Test func performActionCallsActionAndDismisses() {
        let sut = makeSUT()
        var actionCalled = false
        sut.show(message: "Test", actionLabel: "Recover") { actionCalled = true }
        let id = sut.toasts[0].id
        sut.performAction(id)
        #expect(actionCalled)
        #expect(sut.toasts.isEmpty)
    }

    // MARK: - Stacking multiple toasts

    // Behaviour: If the user discards multiple habits in quick succession,
    // each gets its own toast that stacks visually.
    @Test func multipleToastsStack() {
        let sut = makeSUT()
        sut.show(message: "First", actionLabel: "Recover") {}
        sut.show(message: "Second", actionLabel: "Recover") {}
        #expect(sut.toasts.count == 2)
    }

    // Behaviour: Dismissing one toast does not affect the others —
    // each toast operates independently.
    @Test func dismissingOneToastLeavesOthersIntact() {
        let sut = makeSUT()
        sut.show(message: "First", actionLabel: "Recover") {}
        sut.show(message: "Second", actionLabel: "Recover") {}
        let firstId = sut.toasts[0].id
        sut.dismiss(firstId)
        #expect(sut.toasts.count == 1)
        #expect(sut.toasts[0].message == "Second")
    }

    // MARK: - Auto-dismiss timer

    // Behaviour: Toasts automatically disappear after their duration expires
    // so they don't permanently clutter the screen.
    @Test func toastAutoRemovesAfterDuration() async throws {
        let sut = makeSUT()
        // Use a very short duration for testing
        sut.show(message: "Test", actionLabel: "Recover", duration: 1) {}
        #expect(sut.toasts.count == 1)
        // Wait for the timer to expire (1 second + buffer)
        try await Task.sleep(for: .milliseconds(1500))
        #expect(sut.toasts.isEmpty)
    }

    // Behaviour: The countdown timer decrements each second so the user
    // can see how much time remains on the toast.
    @Test func countdownDecrementsEachSecond() async throws {
        let sut = makeSUT()
        sut.show(message: "Test", actionLabel: "Recover", duration: 3) {}
        let id = sut.toasts[0].id
        #expect(sut.remainingSeconds[id] == 3)
        try await Task.sleep(for: .milliseconds(1100))
        #expect(sut.remainingSeconds[id] == 2)
    }

    // Behaviour: some toasts are informational only, like telling the user
    // that completed-task reminders were cleared, so an action button is optional.
    @Test func informationalToastDoesNotRequireActionButton() {
        let sut = makeSUT()
        sut.show(message: "Task reminders cleared", duration: 5)
        #expect(sut.toasts.count == 1)
        #expect(sut.toasts[0].actionLabel == nil)
    }
}
