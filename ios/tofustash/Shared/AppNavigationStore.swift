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

    var tab: AppTab {
        switch self {
        case .task:
            return .tasks
        case .habit:
            return .habits
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

    func clearPendingEntityFormRequest(id: UUID) {
        guard pendingEntityFormRequest?.id == id else { return }
        pendingEntityFormRequest = nil
    }
}
