import Foundation
import SwiftUI

@MainActor
enum NotificationRouteLifecycleCoordinator {
    static func activateQueuedRoute(
        routeStore: NotificationEntityRouteStoring,
        appNavigationStore: AppNavigationStore
    ) {
        guard let route = routeStore.consumeQueuedRoute() else { return }

        switch route {
        case .task(let taskID):
            appNavigationStore.openTaskForm(taskID: taskID)
        case .recurringTask(let recurringTaskID):
            appNavigationStore.openRecurringTaskForm(recurringTaskID: recurringTaskID)
        }
    }
}

private struct NotificationRouteLifecycleTrigger: Equatable {
    let sceneIsActive: Bool
}

private struct NotificationRouteLifecycleModifier: ViewModifier {
    let routeStore: NotificationEntityRouteStoring
    let appNavigationStore: AppNavigationStore
    let scenePhase: ScenePhase
    let notificationCenter: NotificationCenter
    let activationDelay: Duration

    func body(content: Content) -> some View {
        let trigger = NotificationRouteLifecycleTrigger(sceneIsActive: scenePhase == .active)

        content
            .task(id: trigger) {
                guard trigger.sceneIsActive else { return }

                do {
                    try await Task.sleep(for: activationDelay)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                NotificationRouteLifecycleCoordinator.activateQueuedRoute(
                    routeStore: routeStore,
                    appNavigationStore: appNavigationStore
                )
            }
            .onReceive(notificationCenter.publisher(for: .notificationEntityRouteDidChange)) { _ in
                Task { @MainActor in
                    NotificationRouteLifecycleCoordinator.activateQueuedRoute(
                        routeStore: routeStore,
                        appNavigationStore: appNavigationStore
                    )
                }
            }
    }
}

extension View {
    func notificationRouteLifecycle(
        routeStore: NotificationEntityRouteStoring,
        appNavigationStore: AppNavigationStore,
        scenePhase: ScenePhase,
        notificationCenter: NotificationCenter = .default,
        activationDelay: Duration = .milliseconds(300)
    ) -> some View {
        modifier(
            NotificationRouteLifecycleModifier(
                routeStore: routeStore,
                appNavigationStore: appNavigationStore,
                scenePhase: scenePhase,
                notificationCenter: notificationCenter,
                activationDelay: activationDelay
            )
        )
    }
}
