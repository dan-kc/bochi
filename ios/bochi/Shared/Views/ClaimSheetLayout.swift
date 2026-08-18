import SwiftUI

enum ClaimSheetContentStyle {
    case standard
    case quantityPicker

    var topPadding: CGFloat {
        switch self {
        case .standard:
            return 24
        case .quantityPicker:
            return 10
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .standard:
            return 24
        case .quantityPicker:
            return 28
        }
    }
}

private struct ClaimSheetContentLayout: ViewModifier {
    let style: ClaimSheetContentStyle

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .padding()
            .padding(.top, style.topPadding)
    }
}

extension View {
    func claimSheetContentLayout(style: ClaimSheetContentStyle = .standard) -> some View {
        modifier(ClaimSheetContentLayout(style: style))
    }
}

struct ClaimSheetFloatingActionShell<Content: View, FloatingControls: View>: View {
    @Environment(\.bochiTheme) private var theme
    let bottomSpacerHeight: CGFloat
    let contentStyle: ClaimSheetContentStyle
    let content: Content
    let floatingControls: FloatingControls

    init(
        bottomSpacerHeight: CGFloat = 94,
        contentStyle: ClaimSheetContentStyle = .standard,
        @ViewBuilder content: () -> Content,
        @ViewBuilder floatingControls: () -> FloatingControls
    ) {
        self.bottomSpacerHeight = bottomSpacerHeight
        self.contentStyle = contentStyle
        self.content = content()
        self.floatingControls = floatingControls()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    content
                        .claimSheetContentLayout(style: contentStyle)

                    Color.clear
                        .frame(height: bottomSpacerHeight)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            EntityFormFloatingControlFade(height: bottomSpacerHeight)
            EntityFormFloatingControlHitShield()

            floatingControls
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background {
            theme.appBackground()
                .ignoresSafeArea()
        }
    }
}

extension View {
    func claimSheetPresentation(theme: BochiTheme) -> some View {
        self
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.appBackground())
            .presentationContentInteraction(.scrolls)
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
