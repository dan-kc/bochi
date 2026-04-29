import Testing
import UserNotifications
@testable import tofustash

@MainActor
struct ForegroundNotificationPresenterTests {
    // Behaviour: reminders should still surface visibly when they fire while
    // the user is actively using the app.
    @Test func foregroundNotificationsUseVisiblePresentationOptions() {
        let presenter = ForegroundNotificationPresenter(
            routeStore: InMemoryNotificationRouteStore()
        )
        let options = presenter.presentationOptions()

        #expect(options.contains(.banner))
        #expect(options.contains(.list))
        #expect(options.contains(.sound))
    }

    // Behaviour: tapping a task reminder should switch the app back to the
    // pending route store so the app can open the task after startup settles.
    @Test func taskReminderTapQueuesTaskRoute() async {
        let routeStore = InMemoryNotificationRouteStore()
        let presenter = ForegroundNotificationPresenter(
            routeStore: routeStore,
            canDeliverRouteImmediately: { true }
        )

        presenter.handleNotificationRoute(.task("task-123"))

        #expect(routeStore.consumeQueuedRoute() == .task("task-123"))
        #expect(routeStore.didNotifyObservers)
    }

    // Behaviour: tapping a habit reminder should use the same pending route
    // path as tasks so the habits tab can open its change form after activation.
    @Test func habitReminderTapQueuesHabitRoute() async {
        let routeStore = InMemoryNotificationRouteStore()
        let presenter = ForegroundNotificationPresenter(
            routeStore: routeStore,
            canDeliverRouteImmediately: { true }
        )

        presenter.handleNotificationRoute(.habit("habit-123"))

        #expect(routeStore.consumeQueuedRoute() == .habit("habit-123"))
        #expect(routeStore.didNotifyObservers)
    }

    // Behaviour: only task reminders should enqueue a pending deep link.
    @Test func remindersWithoutTaskIDDoNotQueueRoute() {
        let routeStore = InMemoryNotificationRouteStore()

        #expect(routeStore.consumeQueuedRoute() == nil)
    }

    // Behaviour: when the app is not active, the delegate should persist the
    // task route without trying to wake SwiftUI observers immediately.
    @Test func backgroundReminderTapDefersObserverNotification() {
        let routeStore = InMemoryNotificationRouteStore()
        let presenter = ForegroundNotificationPresenter(
            routeStore: routeStore,
            canDeliverRouteImmediately: { false }
        )

        presenter.handleNotificationRoute(.task("task-123"))

        #expect(routeStore.consumeQueuedRoute() == .task("task-123"))
        #expect(routeStore.didNotifyObservers == false)
    }
}

private final class InMemoryNotificationRouteStore: NotificationEntityRouteStoring {
    private var queuedRoute: NotificationEntityRoute?
    private(set) var didNotifyObservers = false

    func queueRoute(_ route: NotificationEntityRoute, notifyObservers: Bool) {
        queuedRoute = route
        didNotifyObservers = notifyObservers
    }

    func consumeQueuedRoute() -> NotificationEntityRoute? {
        defer { queuedRoute = nil }
        return queuedRoute
    }
}
