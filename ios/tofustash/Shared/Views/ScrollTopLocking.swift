import SwiftUI

private struct ScrollTopLockingModifier: ViewModifier {
    @Binding var isAtTop: Bool
    let tolerance: CGFloat

    func body(content: Content) -> some View {
        content
            // SwiftUI exposes scroll metrics declaratively here instead of via an
            // imperative scroll listener. We reduce that geometry to one boolean
            // so the list screens can simply say "controls are enabled at top."
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y <= geometry.contentInsets.top + tolerance
            } action: { _, isAtTop in
                self.isAtTop = isAtTop
            }
    }
}

extension View {
    func lockControlsUnlessScrolledToTop(isAtTop: Binding<Bool>, tolerance: CGFloat = 1) -> some View {
        modifier(ScrollTopLockingModifier(isAtTop: isAtTop, tolerance: tolerance))
    }
}
