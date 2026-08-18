import SwiftUI

private struct EntityListProjectionLifecycleModifier<
    ProjectionToken: Equatable,
    PendingFormToken: Equatable,
    PendingRevealToken: Equatable
>: ViewModifier {
    let projectionToken: ProjectionToken
    let pendingFormToken: PendingFormToken
    let pendingRevealToken: PendingRevealToken
    let selectedTab: AppTab
    let expectedTab: AppTab
    let refreshProjection: () -> Void
    let openPendingForm: () -> Void
    let revealPendingEntity: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                refreshProjection()
                schedulePendingFormOpen()
                schedulePendingReveal()
            }
            .onChange(of: projectionToken) { _, _ in
                refreshProjection()
            }
            .onChange(of: pendingFormToken) { _, _ in
                schedulePendingFormOpen()
            }
            .onChange(of: pendingRevealToken) { _, _ in
                schedulePendingReveal()
            }
            .onChange(of: selectedTab) { _, selectedTab in
                guard selectedTab == expectedTab else { return }
                schedulePendingFormOpen()
                schedulePendingReveal()
            }
    }

    private func schedulePendingFormOpen() {
        EntityListViewCoordinator.scheduleDeferredAction(openPendingForm)
    }

    private func schedulePendingReveal() {
        EntityListViewCoordinator.scheduleDeferredAction(revealPendingEntity)
    }
}

extension View {
    func entityListProjectionLifecycle<
        ProjectionToken: Equatable,
        PendingFormToken: Equatable,
        PendingRevealToken: Equatable
    >(
        projectionToken: ProjectionToken,
        pendingFormToken: PendingFormToken,
        pendingRevealToken: PendingRevealToken,
        selectedTab: AppTab,
        expectedTab: AppTab,
        refreshProjection: @escaping () -> Void,
        openPendingForm: @escaping () -> Void,
        revealPendingEntity: @escaping () -> Void
    ) -> some View {
        modifier(
            EntityListProjectionLifecycleModifier(
                projectionToken: projectionToken,
                pendingFormToken: pendingFormToken,
                pendingRevealToken: pendingRevealToken,
                selectedTab: selectedTab,
                expectedTab: expectedTab,
                refreshProjection: refreshProjection,
                openPendingForm: openPendingForm,
                revealPendingEntity: revealPendingEntity
            )
        )
    }
}
