import SwiftUI

@MainActor
protocol AccountDeletionDataCleaning: AnyObject {
    func deleteLocalAccountData(for userID: String) throws -> AccountDeletionCleanupResult
}

@MainActor
protocol AccountDeletionNotificationCancelling: AnyObject {
    func cancelNotifications(for reminderIDs: [RecordID])
}

extension SyncManager: AccountDeletionDataCleaning {}
extension ReminderNotificationReconciler: AccountDeletionNotificationCancelling {}

@MainActor
enum AccountDeletionLifecycleCoordinator {
    static func reconcile(
        event: AccountDeletionEvent?,
        dataCleaner: AccountDeletionDataCleaning,
        notificationCanceller: AccountDeletionNotificationCancelling
    ) {
        guard let event else { return }

        do {
            let cleanup = try dataCleaner.deleteLocalAccountData(for: event.userID)
            notificationCanceller.cancelNotifications(for: cleanup.reminderIDs)
        } catch {
            assertionFailure("Failed to clean up deleted account data: \(error)")
        }
    }
}

private struct AccountDeletionLifecycleModifier: ViewModifier {
    let authManager: AuthManager
    let dataCleaner: AccountDeletionDataCleaning
    let notificationCanceller: AccountDeletionNotificationCancelling

    func body(content: Content) -> some View {
        let event = authManager.accountDeletionEvent

        content.task(id: event) {
            AccountDeletionLifecycleCoordinator.reconcile(
                event: event,
                dataCleaner: dataCleaner,
                notificationCanceller: notificationCanceller
            )
        }
    }
}

extension View {
    func accountDeletionLifecycle(
        authManager: AuthManager,
        dataCleaner: AccountDeletionDataCleaning,
        notificationCanceller: AccountDeletionNotificationCancelling
    ) -> some View {
        modifier(
            AccountDeletionLifecycleModifier(
                authManager: authManager,
                dataCleaner: dataCleaner,
                notificationCanceller: notificationCanceller
            )
        )
    }
}
