import Foundation
import UIKit
@preconcurrency import UserNotifications

@MainActor
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    private let routeStore: NotificationEntityRouteStoring
    private let canDeliverRouteImmediately: @MainActor () -> Bool

    init(
        routeStore: NotificationEntityRouteStoring,
        canDeliverRouteImmediately: (@MainActor () -> Bool)? = nil
    ) {
        self.routeStore = routeStore
        self.canDeliverRouteImmediately = canDeliverRouteImmediately ?? {
            UIApplication.shared.connectedScenes.contains { scene in
                scene.activationState == .foregroundActive
            }
        }
    }

    // Behaviour: when a reminder fires while the app is already open, still
    // show it as a visible notification instead of silently swallowing it.
    nonisolated func presentationOptions() -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // Behaviour: tapping an entity reminder should take the user straight into
    // that entity's edit sheet once the app has an active SwiftUI scene.
    @MainActor
    func handleNotificationRoute(_ route: NotificationEntityRoute) {
        let shouldNotifyImmediately = canDeliverRouteImmediately()
        routeStore.queueRoute(
            route,
            notifyObservers: shouldNotifyImmediately
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async {
            completionHandler(self.presentationOptions())
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let taskID = response.notification.request.content.userInfo["taskID"] as? String
        let habitID = response.notification.request.content.userInfo["habitID"] as? String
        DispatchQueue.main.async {
            if let taskID {
                self.handleNotificationRoute(.task(RecordID(taskID)))
            } else if let habitID {
                self.handleNotificationRoute(.habit(RecordID(habitID)))
            }
            completionHandler()
        }
    }
}
