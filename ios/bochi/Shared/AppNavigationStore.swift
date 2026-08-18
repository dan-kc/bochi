import Foundation

enum AppTab: Hashable {
    case earn
    case tasks
    case recurringTasks
    case rewards
    case spend
    case vault
    case settings
}

enum PendingEntityFormRoute: Equatable, Sendable {
    case task(RecordID)
    case recurringTask(RecordID)
    case reward(RecordID)

    var tab: AppTab {
        switch self {
        case .task:
            return .earn
        case .recurringTask:
            return .earn
        case .reward:
            return .spend
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
    var selectedTab: AppTab = .earn
    private(set) var rootEntityListControlsAreVisible = true
    private(set) var newEntityFormRoute: NewEntityFormRoute?
    private(set) var newEntityFormDismissAttemptID: UUID?
    private(set) var pendingEntityFormRequest: PendingEntityFormRequest?
    private(set) var pendingEntityRevealRequest: PendingEntityFormRequest?

    var isPresentingNewEntityForm: Bool {
        newEntityFormRoute != nil
    }

    func openNewEntityForm(selectedEntity: EntityFormKind, originTab: AppTab) {
        newEntityFormRoute = NewEntityFormRoute(
            snapshot: EntityFormSwitcherSupport.makeInitialSnapshot(selectedEntity: selectedEntity),
            originTab: originTab
        )
    }

    func openNewEntityForm(snapshot: NewEntityFormSnapshot, originTab: AppTab) {
        newEntityFormRoute = NewEntityFormRoute(
            snapshot: snapshot,
            originTab: originTab
        )
    }

    func dismissNewEntityForm() {
        newEntityFormRoute = nil
        newEntityFormDismissAttemptID = nil
    }

    func requestNewEntityFormDismissAttempt() {
        guard newEntityFormRoute != nil else { return }
        newEntityFormDismissAttemptID = UUID()
    }

    func openTaskForm(taskID: RecordID) {
        selectedTab = .earn
        pendingEntityFormRequest = PendingEntityFormRequest(route: .task(taskID))
    }

    func openRecurringTaskForm(recurringTaskID: RecordID) {
        selectedTab = .earn
        pendingEntityFormRequest = PendingEntityFormRequest(route: .recurringTask(recurringTaskID))
    }

    func openRewardForm(rewardID: RecordID) {
        selectedTab = .spend
        pendingEntityFormRequest = PendingEntityFormRequest(route: .reward(rewardID))
    }

    func clearPendingEntityFormRequest(id: UUID) {
        guard pendingEntityFormRequest?.id == id else { return }
        pendingEntityFormRequest = nil
    }

    func queueEntityReveal(_ route: PendingEntityFormRoute) {
        pendingEntityRevealRequest = PendingEntityFormRequest(route: route)
    }

    func clearPendingEntityRevealRequest(id: UUID) {
        guard pendingEntityRevealRequest?.id == id else { return }
        pendingEntityRevealRequest = nil
    }

    func setRootEntityListControlsVisibility(_ isVisible: Bool, for tab: AppTab) {
        guard selectedTab == tab else { return }
        guard rootEntityListControlsAreVisible != isVisible else { return }

        rootEntityListControlsAreVisible = isVisible
    }

    func resetRootEntityListControlsVisibility() {
        rootEntityListControlsAreVisible = true
    }
}
