import Foundation

extension Notification.Name {
    static let notificationEntityRouteDidChange = Notification.Name("notificationEntityRouteDidChange")
}

enum NotificationEntityRoute: Equatable, Sendable {
    case task(RecordID)
    case habit(RecordID)

    private enum Kind: String {
        case task
        case habit
    }

    fileprivate var rawKind: String {
        switch self {
        case .task:
            return Kind.task.rawValue
        case .habit:
            return Kind.habit.rawValue
        }
    }

    fileprivate var rawID: String {
        switch self {
        case .task(let id), .habit(let id):
            return id.rawValue
        }
    }

    fileprivate static func from(rawKind: String, rawID: String) -> NotificationEntityRoute? {
        guard let kind = Kind(rawValue: rawKind) else { return nil }

        switch kind {
        case .task:
            return .task(RecordID(rawID))
        case .habit:
            return .habit(RecordID(rawID))
        }
    }
}

protocol NotificationEntityRouteStoring: AnyObject {
    func queueRoute(_ route: NotificationEntityRoute, notifyObservers: Bool)
    func consumeQueuedRoute() -> NotificationEntityRoute?
}

final class NotificationTaskRouteStore: NotificationEntityRouteStoring {
    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let queuedRouteKindKey = "notification-route-kind"
    private let queuedRouteIDKey = "notification-route-id"

    init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    func queueRoute(_ route: NotificationEntityRoute, notifyObservers: Bool) {
        userDefaults.set(route.rawKind, forKey: queuedRouteKindKey)
        userDefaults.set(route.rawID, forKey: queuedRouteIDKey)
        if notifyObservers {
            notificationCenter.post(name: .notificationEntityRouteDidChange, object: nil)
        }
    }

    func consumeQueuedRoute() -> NotificationEntityRoute? {
        guard let rawKind = userDefaults.string(forKey: queuedRouteKindKey),
              let rawID = userDefaults.string(forKey: queuedRouteIDKey),
              let route = NotificationEntityRoute.from(rawKind: rawKind, rawID: rawID) else {
            return nil
        }

        userDefaults.removeObject(forKey: queuedRouteKindKey)
        userDefaults.removeObject(forKey: queuedRouteIDKey)
        return route
    }
}
