import SwiftUI

// Shared Liquid Glass button treatment so trade actions and floating controls
// all pick up the system press behaviour without each feature hand-tuning it.
extension View {
    func tofuGlassButton(
        borderShape: ButtonBorderShape = .capsule
    ) -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(borderShape)
    }

    func tofuGlassButton(
        tint: Color,
        tintOpacity: CGFloat = 0.18,
        borderShape: ButtonBorderShape = .capsule
    ) -> some View {
        buttonStyle(.glass(.regular.tint(tint.opacity(tintOpacity))))
            .buttonBorderShape(borderShape)
    }
}
