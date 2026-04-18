import Foundation

enum SyncEntityKind: String, Codable, CaseIterable {
    case habits
    case trades
    case tags
    case habitTags
    case rewards
    case rewardTags
    case generalDifficulty
}

struct SyncMutation: Sendable {
    let ownerID: String
    let entityKind: SyncEntityKind
    let recordIDs: [String]
}

enum SyncMutationCenter {
    private static let notificationName = Notification.Name("tofustash.syncMutation")

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
}
