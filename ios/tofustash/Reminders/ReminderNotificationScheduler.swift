import Foundation
import UserNotifications

struct ReminderNotificationDescriptor: Equatable, Sendable {
    let reminderID: RecordID
    let scheduledAt: Date
    let title: String
    let body: String
    let taskID: RecordID?
    let habitID: RecordID?
}

@MainActor
protocol ReminderNotificationScheduling: AnyObject {
    func syncNotifications(for descriptors: [ReminderNotificationDescriptor])
    func cancelNotifications(for reminderIDs: [RecordID])
}

@MainActor
final class LiveReminderNotificationScheduler: ReminderNotificationScheduling {
    func syncNotifications(for descriptors: [ReminderNotificationDescriptor]) {
        guard !AppRuntimeEnvironment.isUITesting else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let granted = await requestAuthorization(on: center)
            guard granted == true else { return }

            let identifiers = descriptors.map { $0.reminderID.rawValue }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)

            for descriptor in descriptors {
                let content = UNMutableNotificationContent()
                content.title = descriptor.title
                content.body = descriptor.body
                content.sound = .default
                content.userInfo = notificationUserInfo(for: descriptor)

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: descriptor.scheduledAt
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: descriptor.reminderID.rawValue,
                    content: content,
                    trigger: trigger
                )
                await add(request, to: center)
            }
        }
    }

    func cancelNotifications(for reminderIDs: [RecordID]) {
        guard !reminderIDs.isEmpty else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: reminderIDs.map(\.rawValue))
    }

    private func requestAuthorization(on center: UNUserNotificationCenter) async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func add(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) async {
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume(returning: ())
            }
        }
    }

    private func notificationUserInfo(for descriptor: ReminderNotificationDescriptor) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [:]
        if let taskID = descriptor.taskID {
            userInfo["taskID"] = taskID.rawValue
        }
        if let habitID = descriptor.habitID {
            userInfo["habitID"] = habitID.rawValue
        }
        return userInfo
    }
}

@MainActor
final class NoOpReminderNotificationScheduler: ReminderNotificationScheduling {
    func syncNotifications(for descriptors: [ReminderNotificationDescriptor]) { }
    func cancelNotifications(for reminderIDs: [RecordID]) { }
}
