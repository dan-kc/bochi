import SwiftUI

nonisolated enum TimerDisplayTimeline {
    static let refreshInterval: Duration = .milliseconds(16)

    static func shouldRefresh(isRunning: Bool, sceneIsActive: Bool) -> Bool {
        isRunning && sceneIsActive
    }
}

private struct TimerDisplayLifecycleTrigger: Equatable {
    let shouldRefresh: Bool
}

private struct TimerDisplayLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let isRunning: Bool
    let notBefore: ContinuousClock.Instant?
    let onRefresh: @MainActor (ContinuousClock.Instant) -> Void

    private let clock = ContinuousClock()

    func body(content: Content) -> some View {
        let trigger = TimerDisplayLifecycleTrigger(
            shouldRefresh: TimerDisplayTimeline.shouldRefresh(
                isRunning: isRunning,
                sceneIsActive: scenePhase == .active
            )
        )

        content.task(id: trigger) {
            guard trigger.shouldRefresh else { return }

            if let notBefore, clock.now < notBefore {
                do {
                    try await clock.sleep(until: notBefore)
                } catch {
                    return
                }
            }

            while !Task.isCancelled {
                let refreshedAt = clock.now
                onRefresh(refreshedAt)

                do {
                    try await clock.sleep(
                        until: refreshedAt.advanced(by: TimerDisplayTimeline.refreshInterval)
                    )
                } catch {
                    return
                }
            }
        }
    }
}

extension View {
    func timerDisplayLifecycle(
        isRunning: Bool,
        notBefore: ContinuousClock.Instant?,
        onRefresh: @escaping @MainActor (ContinuousClock.Instant) -> Void
    ) -> some View {
        modifier(
            TimerDisplayLifecycleModifier(
                isRunning: isRunning,
                notBefore: notBefore,
                onRefresh: onRefresh
            )
        )
    }
}
