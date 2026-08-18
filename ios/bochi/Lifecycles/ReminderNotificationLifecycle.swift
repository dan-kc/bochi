import SwiftUI

private struct ReminderNotificationLifecycleTrigger: Equatable {
    let revision: Int
    let hasPremiumAccess: Bool
    let sceneIsActive: Bool
}

private struct ReminderNotificationLifecycleModifier: ViewModifier {
    let reminderStore: ReminderStore
    let notificationReconciler: ReminderNotificationReconciler
    let hasPremiumAccess: Bool
    let scenePhase: ScenePhase

    func body(content: Content) -> some View {
        let trigger = ReminderNotificationLifecycleTrigger(
            revision: reminderStore.notificationScheduleRevision,
            hasPremiumAccess: hasPremiumAccess,
            sceneIsActive: scenePhase == .active
        )

        content.task(id: trigger) {
            guard trigger.sceneIsActive else { return }
            notificationReconciler.reconcileNotifications(hasPremiumAccess: trigger.hasPremiumAccess)
        }
    }
}

extension View {
    func reminderNotificationLifecycle(
        reminderStore: ReminderStore,
        notificationReconciler: ReminderNotificationReconciler,
        hasPremiumAccess: Bool,
        scenePhase: ScenePhase
    ) -> some View {
        modifier(
            ReminderNotificationLifecycleModifier(
                reminderStore: reminderStore,
                notificationReconciler: notificationReconciler,
                hasPremiumAccess: hasPremiumAccess,
                scenePhase: scenePhase
            )
        )
    }
}
