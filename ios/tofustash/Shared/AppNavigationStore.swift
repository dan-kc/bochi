import Foundation

enum AppTab: Hashable {
    case tasks
    case habits
    case rewards
    case settings
}

enum PendingEntityFormRoute: Equatable, Sendable {
    case task(RecordID)
    case habit(RecordID)
    case reward(RecordID)

    var tab: AppTab {
        switch self {
        case .task:
            return .tasks
        case .habit:
            return .habits
        case .reward:
            return .rewards
        }
    }
}

struct PendingEntityFormRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let route: PendingEntityFormRoute
}

@Observable
@MainActor
final class AppNavigationStore {
    var selectedTab: AppTab = .tasks
    private(set) var pendingEntityFormRequest: PendingEntityFormRequest?

    func openTaskForm(taskID: RecordID) {
        selectedTab = .tasks
        pendingEntityFormRequest = PendingEntityFormRequest(route: .task(taskID))
    }

    func openHabitForm(habitID: RecordID) {
        selectedTab = .habits
        pendingEntityFormRequest = PendingEntityFormRequest(route: .habit(habitID))
    }

    func openRewardForm(rewardID: RecordID) {
        selectedTab = .rewards
        pendingEntityFormRequest = PendingEntityFormRequest(route: .reward(rewardID))
    }

    func clearPendingEntityFormRequest(id: UUID) {
        guard pendingEntityFormRequest?.id == id else { return }
        pendingEntityFormRequest = nil
    }
}
