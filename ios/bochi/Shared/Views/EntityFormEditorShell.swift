import SwiftUI

struct EntityFormEditorShell<Switcher: View, TextFields: View, ExtraContent: View, FloatingControls: View>: View {
    @Environment(\.bochiTheme) private var theme
    let isEditingText: Bool
    let valuePills: [PillItem]
    let detailPills: [PillItem]
    let tags: [Tag]
    let activitySummary: String?
    let bottomSpacerHeight: CGFloat
    let pillTransitionStyle: PillRowTransitionStyle
    let onTagsTapped: () -> Void
    let switcher: Switcher
    let textFields: TextFields
    let extraContent: ExtraContent
    let floatingControls: FloatingControls

    init(
        isEditingText: Bool,
        valuePills: [PillItem],
        detailPills: [PillItem],
        tags: [Tag],
        activitySummary: String? = nil,
        bottomSpacerHeight: CGFloat,
        pillTransitionStyle: PillRowTransitionStyle = .standard,
        onTagsTapped: @escaping () -> Void,
        @ViewBuilder switcher: () -> Switcher,
        @ViewBuilder textFields: () -> TextFields,
        @ViewBuilder extraContent: () -> ExtraContent,
        @ViewBuilder floatingControls: () -> FloatingControls
    ) {
        self.isEditingText = isEditingText
        self.valuePills = valuePills
        self.detailPills = detailPills
        self.tags = tags
        self.activitySummary = activitySummary
        self.bottomSpacerHeight = bottomSpacerHeight
        self.pillTransitionStyle = pillTransitionStyle
        self.onTagsTapped = onTagsTapped
        self.switcher = switcher()
        self.textFields = textFields()
        self.extraContent = extraContent()
        self.floatingControls = floatingControls()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hiddenWhileTyping {
                        switcher
                            .padding(.horizontal, 16)
                    }

                    textFields
                        .padding(.horizontal, 16)

                    hiddenWhileTyping {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledPillRow(title: "Price influencing", pills: valuePills, leadingInset: 16, trailingInset: 16, transitionStyle: pillTransitionStyle)
                            LabeledPillRow(title: "Details", pills: detailPills, leadingInset: 16, trailingInset: 16, transitionStyle: pillTransitionStyle)
                            PremiumRenewalNoticeLines(notices: EntityFormSupport.premiumRenewalNotices(for: detailPills))
                        }
                    }

                    if !tags.isEmpty {
                        hiddenWhileTyping {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tags")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(theme.secondaryText())
                                    .padding(.horizontal, 16)

                                TagPillsRow(tags: tags, size: .form, leadingInset: 16)
                                    .contentShape(Rectangle())
                                    .onTapGesture(perform: onTagsTapped)
                            }
                        }
                    }

                    hiddenWhileTyping {
                        extraContent
                            .padding(.horizontal, 16)
                    }

                    if let activitySummary {
                        hiddenWhileTyping {
                            Text(activitySummary)
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText())
                                .padding(.horizontal, 16)
                        }
                    }

                    Color.clear
                        .frame(height: bottomSpacerHeight)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            hiddenWhileTyping {
                if showsFloatingControlFade {
                    EntityFormFloatingControlFade(height: bottomSpacerHeight)
                    EntityFormFloatingControlHitShield()
                }
            }

            hiddenWhileTyping {
                floatingControls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background {
            theme.appBackground()
                .ignoresSafeArea()
        }
        .foregroundStyle(theme.primaryText())
    }

    private func hiddenWhileTyping<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(isEditingText ? 0 : 1)
            .allowsHitTesting(!isEditingText)
    }

    private var showsFloatingControlFade: Bool {
        bottomSpacerHeight > 16
    }
}

struct EntityFormFloatingControlHitShield: View {
    private static let actionHeight: CGFloat = 50
    private static let actionBottomPadding: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    // Behaviour: tapping the faded action area should not
                    // activate scrolled form controls hidden underneath it.
                    .onTapGesture { }
                    .frame(height: shieldHeight + geometry.safeAreaInsets.bottom)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityHidden(true)
    }

    private var shieldHeight: CGFloat {
        Self.actionHeight + Self.actionBottomPadding
    }
}

struct EntityFormFloatingControlFade: View {
    @Environment(\.bochiTheme) private var theme
    private static let fadeExtensionHeight: CGFloat = 24
    private static let actionBottomPadding: CGFloat = 12
    private static let remainingContentOpacity: CGFloat = 0.15

    let height: CGFloat

    var body: some View {
        // Behaviour: scrolled form content should soften behind the bottom
        // action without disappearing completely.
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                LinearGradient(
                    stops: [
                        .init(color: theme.appBackground().opacity(0), location: 0),
                        .init(color: fadedBackgroundColor, location: solidStartLocation),
                        .init(color: fadedBackgroundColor, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: gradientHeight)

                fadedBackgroundColor
                    .frame(height: geometry.safeAreaInsets.bottom)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var gradientHeight: CGFloat {
        height + Self.fadeExtensionHeight
    }

    private var solidStartLocation: CGFloat {
        (gradientHeight - Self.actionBottomPadding) / gradientHeight
    }

    private var fadedBackgroundColor: Color {
        theme.appBackground().opacity(1 - Self.remainingContentOpacity)
    }
}

struct PremiumRenewalNoticeLines: View {
    @Environment(\.bochiTheme) private var theme
    let notices: [String]

    var body: some View {
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(notices, id: \.self) { notice in
                    Text(notice)
                        .font(.caption)
                        .fontWeight(.regular)
                        .foregroundStyle(theme.premiumText())
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct EntityFormStaticTraitBadges: View {
    @Environment(\.bochiTheme) private var theme
    let entity: String
    let cadence: String

    var body: some View {
        HStack(spacing: 8) {
            badge(entity)
            badge(cadence)
        }
        .accessibilityElement(children: .combine)
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .textCase(.lowercase)
            .foregroundStyle(theme.primaryText())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.componentBackground(), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(theme.secondaryText().opacity(0.28), lineWidth: 1)
            }
    }
}

extension View {
    func entityFormPresentation(theme: BochiTheme, isEditingText: Bool) -> some View {
        self
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.appBackground())
            .presentationContentInteraction(.scrolls)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .animation(.easeInOut(duration: 0.18), value: isEditingText)
    }
}
