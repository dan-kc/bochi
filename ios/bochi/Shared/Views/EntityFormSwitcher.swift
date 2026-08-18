import SwiftUI

extension EntityFormKind {
    var themeRole: BochiThemeRole {
        switch self {
        case .task:
            return .task
        case .recurringTask:
            return .recurringTask
        case .reward:
            return .reward
        }
    }
}

struct EntityFormSwitcher: View {
    @Environment(\.bochiTheme) private var theme
    let selectedEntity: EntityFormKind
    let onSelect: ((EntityFormKind) -> Void)?

    private var showsAllEntities: Bool {
        onSelect != nil
    }

    private var layout: EntityFormSwitcherLayout {
        EntityFormSwitcherSupport.layout(hasEntitySelection: showsAllEntities)
    }

    var body: some View {
        Group {
            switch layout {
            case .segmentedControl:
                HStack(spacing: 10) {
                    ForEach(EntityFormKind.allCases) { entity in
                        entityButton(entity)
                    }
                }
            case .compactLabel:
                entityLabel(selectedEntity, isSelected: true)
            }
        }
    }

    private func entityButton(_ entity: EntityFormKind) -> some View {
        Button {
            guard entity != selectedEntity else { return }
            onSelect?(entity)
        } label: {
            entityLabel(entity, isSelected: entity == selectedEntity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func entityLabel(_ entity: EntityFormKind, isSelected: Bool) -> some View {
        if isSelected {
            Text(entity.title)
                .font(.callout)
                .frame(maxWidth: layout == .segmentedControl ? .infinity : nil)
                .foregroundStyle(theme.primaryText())
                .padding(.horizontal, layout == .compactLabel ? 10 : 14)
                .padding(.vertical, layout == .compactLabel ? 5 : 10)
                .background(theme.selectedBackground(for: .neutral), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(theme.strongBorder(for: .neutral), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            Text(entity.title)
                .font(layout == .compactLabel ? .caption : .subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(theme.secondaryText())
                .frame(maxWidth: layout == .segmentedControl ? .infinity : nil)
                .padding(.horizontal, layout == .compactLabel ? 10 : 14)
                .padding(.vertical, layout == .compactLabel ? 5 : 10)
                .background(theme.componentBackground(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity(0.55)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var cornerRadius: CGFloat {
        layout == .compactLabel ? 8 : 14
    }
}
