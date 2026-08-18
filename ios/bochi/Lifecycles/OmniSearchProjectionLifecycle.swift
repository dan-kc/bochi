import SwiftUI

private struct OmniSearchProjectionLifecycleModifier<ProjectionToken: Equatable>: ViewModifier {
    let query: String
    let projectionToken: ProjectionToken
    let appear: () -> Void
    let disappear: () -> Void
    let queryChanged: (String, String) -> Void
    let refreshProjection: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: appear)
            .onDisappear(perform: disappear)
            .onChange(of: query, queryChanged)
            .onChange(of: projectionToken) { _, _ in
                refreshProjection()
            }
    }
}

extension View {
    func omniSearchProjectionLifecycle<ProjectionToken: Equatable>(
        query: String,
        projectionToken: ProjectionToken,
        appear: @escaping () -> Void,
        disappear: @escaping () -> Void,
        queryChanged: @escaping (String, String) -> Void,
        refreshProjection: @escaping () -> Void
    ) -> some View {
        modifier(
            OmniSearchProjectionLifecycleModifier(
                query: query,
                projectionToken: projectionToken,
                appear: appear,
                disappear: disappear,
                queryChanged: queryChanged,
                refreshProjection: refreshProjection
            )
        )
    }
}
