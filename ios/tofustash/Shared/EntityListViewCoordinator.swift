import SwiftUI

enum EntityListViewCoordinator {
    static func showDiscardToast<Snapshot, Route>(
        toastManager: ToastManager,
        entityName: String,
        snapshot: Snapshot,
        makeRoute: @escaping (Snapshot) -> Route,
        setRoute: @escaping (Route) -> Void
    ) {
        toastManager.show(
            message: "\(entityName) Discarded",
            actionLabel: "Recover"
        ) {
            setRoute(makeRoute(snapshot))
        }
    }

    static func queueScrollToVisibleItem<ID: Equatable>(
        _ itemID: ID,
        visibleIDs: [ID],
        highlightedID: inout ID?,
        pendingScrollTargetID: inout ID?
    ) {
        guard visibleIDs.contains(itemID) else { return }
        highlightedID = itemID
        pendingScrollTargetID = itemID
    }

    static func scheduleHighlightFade<ID: Equatable>(
        for itemID: ID,
        highlightedID: @escaping () -> ID?,
        setHighlightedID: @escaping (ID?) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard highlightedID() == itemID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                setHighlightedID(nil)
            }
        }
    }

    @MainActor
    static func openPendingFormIfNeeded<Entity>(
        expectedTab: AppTab,
        selectedTab: AppTab,
        request: PendingEntityFormRequest?,
        extractID: (PendingEntityFormRoute) -> RecordID?,
        resolveEntity: (RecordID) -> Entity?,
        isPresentingForm: Bool,
        open: (Entity) -> Void,
        clearRequest: (UUID) -> Void
    ) {
        guard selectedTab == expectedTab else { return }
        guard let request else { return }
        guard let entityID = extractID(request.route) else { return }
        guard let entity = resolveEntity(entityID) else { return }
        guard !isPresentingForm else { return }
        open(entity)
        clearRequest(request.id)
    }

    static func schedulePendingFormOpen(_ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }
}
