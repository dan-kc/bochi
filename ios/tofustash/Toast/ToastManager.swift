import Foundation

// A single toast notification — like a snackbar in Material Design or
// a toast in Android. Each toast has a message, an action button (e.g.
// "Recover"), and a countdown timer before it auto-dismisses.
//
// In React terms, this is the data shape for one toast item in a
// toast notification array (like what react-hot-toast manages).
struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
    let actionLabel: String
    // The closure to run when the user taps the action button.
    // Stored as a non-Sendable closure — always called on MainActor.
    let action: () -> Void
    let duration: TimeInterval
}

// Manages a stack of toast notifications with countdown timers.
// Like a toast/snackbar manager in React (e.g. react-hot-toast's useToaster
// hook) — holds the array of active toasts, handles adding, dismissing,
// and auto-removing them after a timeout.
//
// @Observable makes this work like a React context provider — any SwiftUI
// view that reads a property will re-render when that property changes.
@Observable
class ToastManager {
    // The currently visible toasts — newest last. Views read this to
    // render the toast stack. Like a useState<ToastItem[]>([]) in React.
    private(set) var toasts: [ToastItem] = []

    // Countdown seconds remaining for each toast, keyed by toast ID.
    // Views read this to show "3s", "2s", "1s" on each toast.
    // Like a Map<string, number> state in React.
    private(set) var remainingSeconds: [UUID: Int] = [:]

    // Background tasks that tick down each toast's timer.
    // Not @Observable — these are internal implementation details.
    // Like storing setInterval IDs to clear them on dismiss.
    private var timerTasks: [UUID: Task<Void, Never>] = [:]

    // Show a new toast with a message, action button, and countdown timer.
    // duration: how many seconds before auto-dismiss (default 5).
    // action: closure to run if the user taps the action button (e.g. recover a habit).
    func show(
        message: String,
        actionLabel: String,
        duration: TimeInterval = 5,
        action: @escaping () -> Void
    ) {
        let toast = ToastItem(
            message: message,
            actionLabel: actionLabel,
            action: action,
            duration: duration
        )
        toasts.append(toast)
        remainingSeconds[toast.id] = Int(duration)
        startTimer(for: toast)
    }

    // Remove a toast immediately — called when the user swipes it away,
    // taps the close button, or the timer expires.
    func dismiss(_ id: UUID) {
        timerTasks[id]?.cancel()
        timerTasks[id] = nil
        remainingSeconds[id] = nil
        toasts.removeAll { $0.id == id }
    }

    // Run the toast's action (e.g. recover a discarded habit) and dismiss it.
    // Called when the user taps the action button on the toast.
    func performAction(_ id: UUID) {
        if let toast = toasts.first(where: { $0.id == id }) {
            toast.action()
        }
        dismiss(id)
    }

    // Start a background countdown that decrements remainingSeconds every
    // second and auto-dismisses when it hits zero. Like setInterval in JS,
    // but using Swift's structured concurrency (Task + sleep).
    private func startTimer(for toast: ToastItem) {
        timerTasks[toast.id] = Task {
            let totalSeconds = Int(toast.duration)
            for i in 1...totalSeconds {
                try? await Task.sleep(for: .seconds(1))
                // Task.isCancelled is checked after each sleep — if dismiss()
                // was called while sleeping, we bail out. Like checking a
                // clearInterval flag inside a setInterval callback.
                if Task.isCancelled { return }
                let remaining = totalSeconds - i
                remainingSeconds[toast.id] = remaining
                if remaining == 0 {
                    dismiss(toast.id)
                    return
                }
            }
        }
    }
}
