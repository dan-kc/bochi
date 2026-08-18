import Foundation
import Testing
import UserNotifications
@testable import bochi

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

        #expect(routeStore.consumeQueuedTaskID() == "task-123")
        #expect(routeStore.didNotifyObservers)
    }

    // Behaviour: tapping a recurringTask reminder should use the same pending route
    // path as tasks so the recurringTasks tab can open its change form after activation.
    @Test func recurringTaskReminderTapQueuesRecurringTaskRoute() async {
        let routeStore = InMemoryNotificationRouteStore()
        let presenter = ForegroundNotificationPresenter(
            routeStore: routeStore,
            canDeliverRouteImmediately: { true }
        )

        presenter.handleNotificationRoute(.recurringTask("recurringTask-123"))

        #expect(routeStore.consumeQueuedRecurringTaskID() == "recurringTask-123")
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

        #expect(routeStore.consumeQueuedTaskID() == "task-123")
        #expect(routeStore.didNotifyObservers == false)
    }
}

@MainActor
struct NotificationTaskRouteStoreTests {
    private func makeSuiteName() -> String {
        "bochi-notification-route-\(UUID().uuidString)"
    }

    // Behaviour: queued task routes should survive through UserDefaults until
    // app activation consumes them, and then they should be cleared.
    @Test func taskRoutePersistsAndConsumesOnce() {
        let suiteName = makeSuiteName()
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NotificationTaskRouteStore(userDefaults: defaults, notificationCenter: NotificationCenter())

        store.queueRoute(.task("task-123"), notifyObservers: false)

        #expect(store.consumeQueuedTaskID() == "task-123")
        #expect(store.consumeQueuedRoute() == nil)
        #expect(defaults.string(forKey: "notification-route-kind") == nil)
        #expect(defaults.string(forKey: "notification-route-id") == nil)
    }

    // Behaviour: queued recurringTask routes use the same durable handoff path as task
    // routes so notification navigation works for both reminder owners.
    @Test func recurringTaskRoutePersistsAndConsumesOnce() {
        let suiteName = makeSuiteName()
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NotificationTaskRouteStore(userDefaults: defaults, notificationCenter: NotificationCenter())

        store.queueRoute(.recurringTask("recurringTask-123"), notifyObservers: false)

        #expect(store.consumeQueuedRecurringTaskID() == "recurringTask-123")
        #expect(store.consumeQueuedRoute() == nil)
    }

    // Behaviour: corrupt stored route data should not crash or produce a bogus
    // navigation target.
    @Test func invalidStoredRouteIsIgnored() {
        let suiteName = makeSuiteName()
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("reward", forKey: "notification-route-kind")
        defaults.set("reward-123", forKey: "notification-route-id")
        let store = NotificationTaskRouteStore(userDefaults: defaults, notificationCenter: NotificationCenter())

        #expect(store.consumeQueuedRoute() == nil)
    }

    // Behaviour: foreground notification taps should notify SwiftUI observers
    // immediately, while background taps should only persist the pending route.
    @Test func observerNotificationOnlyPostsWhenRequested() async {
        let suiteName = makeSuiteName()
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notificationCenter = NotificationCenter()
        let store = NotificationTaskRouteStore(userDefaults: defaults, notificationCenter: notificationCenter)
        var observerCallCount = 0
        let observer = notificationCenter.addObserver(
            forName: .notificationEntityRouteDidChange,
            object: nil,
            queue: nil
        ) { _ in
            observerCallCount += 1
        }
        defer { notificationCenter.removeObserver(observer) }

        store.queueRoute(.task("task-background"), notifyObservers: false)
        store.queueRoute(.recurringTask("recurringTask-foreground"), notifyObservers: true)

        #expect(observerCallCount == 1)
        #expect(store.consumeQueuedRecurringTaskID() == "recurringTask-foreground")
    }
}

@MainActor
private extension NotificationEntityRouteStoring {
    func consumeQueuedTaskID() -> RecordID? {
        guard case .task(let id) = consumeQueuedRoute() else { return nil }
        return id
    }

    func consumeQueuedRecurringTaskID() -> RecordID? {
        guard case .recurringTask(let id) = consumeQueuedRoute() else { return nil }
        return id
    }
}

@MainActor
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
