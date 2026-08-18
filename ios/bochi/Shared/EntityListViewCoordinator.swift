import SwiftUI

enum EntityListViewCoordinator {
    private static let highlightFadeDelay: TimeInterval = 0.75
    private static let highlightFadeDuration: TimeInterval = 1.2

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
        DispatchQueue.main.asyncAfter(deadline: .now() + highlightFadeDelay) {
            guard highlightedID() == itemID else { return }
            // Behaviour: keep the row glow fading while the scroll animation is
            // settling so the user can visually connect the movement to the row.
            withAnimation(.easeOut(duration: highlightFadeDuration)) {
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

    static func scheduleDeferredAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }
}
