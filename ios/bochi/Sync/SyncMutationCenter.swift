import Foundation

// Sync flow: stores publish lightweight dirty-record events here; the SwiftUI
// mutation lifecycle debounces them into syncNow().
enum SyncEntityKind: String, Codable, CaseIterable {
    case timers
    case tasks
    case recurringTasks
    case trades
    case tags
    case taskTags
    case taskTaskDependencies
    case taskRecurringTaskDependencies
    case recurringTaskTags
    case rewards
    case rewardTaskDependencies
    case rewardRecurringTaskDependencies
    case rewardTags
    case themePalettes
}

struct SyncMutation: Sendable {
    let ownerID: String
    let entityKind: SyncEntityKind
    let recordIDs: [RecordID]
}

private final class SyncMutationObserverBox: @unchecked Sendable {
    let observer: NSObjectProtocol

    init(_ observer: NSObjectProtocol) {
        self.observer = observer
    }
}

enum SyncMutationCenter {
    private static let notificationName = Notification.Name("bochi.syncMutation")

    static func post(_ mutation: SyncMutation) {
        NotificationCenter.default.post(name: notificationName, object: mutation)
    }

    static func observe(using handler: @escaping @Sendable (SyncMutation) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard let mutation = notification.object as? SyncMutation else { return }
            handler(mutation)
        }
    }

    static func mutations() -> AsyncStream<SyncMutation> {
        AsyncStream { continuation in
            let observerBox = SyncMutationObserverBox(observe { mutation in
                continuation.yield(mutation)
            })
            continuation.onTermination = { _ in
                Task { @MainActor in
                    NotificationCenter.default.removeObserver(observerBox.observer)
                }
            }
        }
    }
}
