import SwiftUI
import UIKit

enum BochiThemeRole: CaseIterable, Hashable {
    case neutral
    case task
    case recurringTask
    case reward
    case settings
}


enum BochiThemePaletteName: String, CaseIterable, Codable, Hashable {
    case paper
    case cotton
    case porcelain
    case ink
    case yellow // Bad
    case amber // Bad
    case orange // Okay
    case tomato // Good, pencily
    case red // Okay, deep red
    case ruby // Okay, pinky
    case crimson // Okay, pinky
    case pink // Okay, v pinky
    case plum // Okay, femme purply
    case purple // Meh
    case violet // Good
    case iris // Meh
    case indigo // Meh
    case blue // Good
    case cyan // Meh
    case teal  // Meh
    case jade // Very nice, papery
    case green // Nice, less papery
    case grass // Good
    case lime // Bad
    case mint // Very nice, hard to distinguish between green and blue
    case sky // Great
}

struct BochiThemePalettePreferences: Codable, Equatable, Hashable {
    var main: BochiThemePaletteName
    var accent: BochiThemeAccentChoice

    static let `default` = BochiThemePalettePreferences(
        main: .porcelain,
        accent: .semantic
    )
}

enum BochiThemeAccentChoice: Codable, Equatable, Hashable {
    case semantic
    case palette(BochiThemePaletteName)

    init?(rawValue: String) {
        if rawValue == Self.semanticRawValue {
            self = .semantic
        } else if let palette = BochiThemePaletteName(rawValue: rawValue) {
            self = .palette(palette)
        } else {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .semantic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var rawValue: String {
        switch self {
        case .semantic:
            return Self.semanticRawValue
        case .palette(let palette):
            return palette.rawValue
        }
    }

    var displayName: String {
        switch self {
        case .semantic:
            return "Semantic"
        case .palette(let palette):
            return palette.displayName
        }
    }

    var paletteName: BochiThemePaletteName? {
        guard case .palette(let palette) = self else { return nil }
        return palette
    }

    private static let semanticRawValue = "semantic"
}

extension BochiThemePaletteName {
    var displayName: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}

enum EntityListColorStrategy {
    case standard
    case rolePalette

    var usesRolePalette: Bool {
        self == .rolePalette
    }

    func appBackground(for _: BochiThemeRole, theme: BochiTheme) -> Color {
        theme.appBackground()
    }

    func primaryText(for role: BochiThemeRole, theme: BochiTheme) -> Color {
        usesRolePalette ? theme.highContrastText(for: role) : theme.primaryText()
    }

    func secondaryText(for role: BochiThemeRole, theme: BochiTheme) -> Color {
        usesRolePalette ? theme.lowContrastText(for: role) : theme.secondaryText()
    }

    func componentBackground(for role: BochiThemeRole, theme: BochiTheme, isRoleSelected: Bool = false) -> Color {
        let selectedRole = usesRolePalette || isRoleSelected ? role : .neutral
        return theme.componentBackground(for: selectedRole)
    }

    func subtleBorder(for role: BochiThemeRole, theme: BochiTheme, isRoleSelected: Bool = false) -> Color {
        let selectedRole = usesRolePalette || isRoleSelected ? role : .neutral
        return theme.subtleBorder(for: selectedRole)
    }

    func interactiveBorder(for role: BochiThemeRole, theme: BochiTheme, isRoleSelected: Bool = false) -> Color {
        if usesRolePalette || isRoleSelected {
            return theme.interactiveBorder(for: role)
        }

        return theme.subtleBorder()
    }
}

private struct EntityListColorStrategyKey: EnvironmentKey {
    static let defaultValue: EntityListColorStrategy = .standard
}

extension EnvironmentValues {
    var entityListColorStrategy: EntityListColorStrategy {
        get { self[EntityListColorStrategyKey.self] }
        set { self[EntityListColorStrategyKey.self] = newValue }
    }
}

struct BochiTheme: Equatable, Hashable {
    static let `default` = BochiTheme(palettes: .default)
    static let selectablePalettes: [BochiThemePaletteName] = BochiThemePaletteName.allCases
    static let premiumPalette: BochiThemePaletteName = .violet
    let palettes: BochiThemePalettePreferences

    init(palettes: BochiThemePalettePreferences = .default) {
        self.palettes = palettes
    }

    private func color(_ step: Int, role: BochiThemeRole) -> Color {
        Self.color(step, palette: paletteName(for: role))
    }

    private static func color(_ step: Int, palette: BochiThemePaletteName) -> Color {
        radixPalette(named: palette).color(step)
    }

    func uiColor(_ step: Int, role: BochiThemeRole) -> UIColor {
        Self.radixPalette(named: paletteName(for: role)).uiColor(step)
    }

    static func uiColor(_ step: Int, palette: BochiThemePaletteName) -> UIColor {
        radixPalette(named: palette).uiColor(step)
    }

    func componentBackground(for role: BochiThemeRole = .neutral) -> Color {
        color(3, role: role)
    }

    static func componentBackground(palette: BochiThemePaletteName) -> Color {
        color(3, palette: palette)
    }

    func selectedComponentBackground(for role: BochiThemeRole = .neutral) -> Color {
        color(5, role: role)
    }

    func appBackground() -> Color {
        color(1, role: .neutral)
    }

    func appBackgroundUIColor() -> UIColor {
        uiColor(1, role: .neutral)
    }

    func primaryText() -> Color {
        color(12, role: .neutral)
    }

    func secondaryText() -> Color {
        color(11, role: .neutral)
    }

    func disabledText() -> Color {
        secondaryText().opacity(0.65)
    }

    func primaryTextUIColor() -> UIColor {
        uiColor(12, role: .neutral)
    }

    func secondaryTextUIColor() -> UIColor {
        uiColor(11, role: .neutral)
    }

    func positiveText() -> Color {
        Self.color(11, palette: .green)
    }

    func warningText() -> Color {
        Self.color(11, palette: .amber)
    }

    func infoText() -> Color {
        Self.color(11, palette: .sky)
    }

    func destructiveText() -> Color {
        Self.color(11, palette: deletePalette())
    }

    func premiumText() -> Color {
        Self.color(11, palette: Self.premiumPalette)
    }

    func premiumFill() -> Color {
        Self.color(9, palette: Self.premiumPalette)
    }

    func premiumBackground() -> Color {
        Self.color(4, palette: Self.premiumPalette)
    }

    func completedTaskCheckmarkFill(hasPremiumAccess: Bool) -> Color {
        Self.color(9, palette: completedTaskCheckmarkPalette(hasPremiumAccess: hasPremiumAccess))
    }

    func completedTaskCheckmarkUIColor(hasPremiumAccess: Bool) -> UIColor {
        Self.uiColor(9, palette: completedTaskCheckmarkPalette(hasPremiumAccess: hasPremiumAccess))
    }

    func taskRefundAmountText(hasPremiumAccess: Bool) -> Color {
        Self.color(9, palette: taskRefundAmountPalette(hasPremiumAccess: hasPremiumAccess))
    }

    func taskRefundAmountUIColor(hasPremiumAccess: Bool) -> UIColor {
        Self.uiColor(9, palette: taskRefundAmountPalette(hasPremiumAccess: hasPremiumAccess))
    }

    func rewardRefundAmountText(hasPremiumAccess: Bool) -> Color {
        Self.color(9, palette: rewardRefundAmountPalette(hasPremiumAccess: hasPremiumAccess))
    }

    func rewardRefundAmountUIColor(hasPremiumAccess: Bool) -> UIColor {
        Self.uiColor(9, palette: rewardRefundAmountPalette(hasPremiumAccess: hasPremiumAccess))
    }

    func selectedBackground(for role: BochiThemeRole) -> Color {
        color(4, role: role)
    }

    func subtleBorder(for role: BochiThemeRole = .neutral) -> Color {
        color(6, role: role)
    }

    static func subtleBorder(palette: BochiThemePaletteName) -> Color {
        color(6, palette: palette)
    }

    func interactiveBorder(for role: BochiThemeRole) -> Color {
        color(7, role: role)
    }

    static func interactiveBorder(palette: BochiThemePaletteName) -> Color {
        color(7, palette: palette)
    }

    func strongBorder(for role: BochiThemeRole) -> Color {
        color(8, role: role)
    }

    func solidFill(for role: BochiThemeRole) -> Color {
        color(9, role: role)
    }

    static func solidFill(palette: BochiThemePaletteName) -> Color {
        color(9, palette: palette)
    }

    func accentComponentBackground(for role: BochiThemeRole) -> Color {
        Self.color(3, palette: accentPalette(for: role))
    }

    func accentInteractiveBorder(for role: BochiThemeRole) -> Color {
        Self.color(7, palette: accentPalette(for: role))
    }

    func accentSolidFill(for role: BochiThemeRole) -> Color {
        Self.color(9, palette: accentPalette(for: role))
    }

    func accentUIColor(_ step: Int, for role: BochiThemeRole) -> UIColor {
        Self.radixPalette(named: accentPalette(for: role)).uiColor(step)
    }

    func tabTint(for tab: AppTab) -> Color {
        solidFill(for: Self.role(for: tab))
    }

    func tabTint(for role: BochiThemeRole) -> Color {
        solidFill(for: role)
    }

    func solidFillHover(for role: BochiThemeRole) -> Color {
        color(10, role: role)
    }

    static func solidFillHover(palette: BochiThemePaletteName) -> Color {
        color(10, palette: palette)
    }

    func lowContrastText(for role: BochiThemeRole) -> Color {
        color(11, role: role)
    }

    func highContrastText(for role: BochiThemeRole = .neutral) -> Color {
        color(12, role: role)
    }

    static func highContrastText(palette: BochiThemePaletteName) -> Color {
        color(12, palette: palette)
    }

    static let tagPickerPalettes: [BochiThemePaletteName] = [
        .yellow, .amber, .orange, .tomato, .red, .ruby,
        .crimson, .pink, .plum, .purple, .violet, .iris,
        .indigo, .blue, .cyan, .teal, .jade, .green,
        .grass, .lime, .mint, .sky
    ]

    static func tagPickerStoredHex(for palette: BochiThemePaletteName) -> String {
        radixPalette(named: palette).hex(11, colorScheme: .light)
    }

    static func tagPickerPreviewColors(
        for palette: BochiThemePaletteName,
        colorScheme: UIUserInterfaceStyle
    ) -> (backgroundHex: String, foregroundHex: String, borderHex: String) {
        let radixPalette = radixPalette(named: palette)
        return (
            backgroundHex: radixPalette.hex(3, colorScheme: colorScheme),
            foregroundHex: radixPalette.hex(11, colorScheme: colorScheme),
            borderHex: radixPalette.hex(6, colorScheme: colorScheme)
        )
    }

    static func tagPickerSwatchColor(for palette: BochiThemePaletteName) -> Color {
        color(11, palette: palette)
    }

    static func tagSwatchColor(hex: String) -> Color {
        guard let palette = paletteName(forTagHex: hex) else {
            return Color(hex: hex)
        }

        return color(11, palette: palette)
    }

    static func tagHex(_ hex: String, matches palette: BochiThemePaletteName) -> Bool {
        paletteName(forTagHex: hex) == palette
    }

    static func normalizedTagPickerStoredHex(for hex: String) -> String? {
        guard let palette = paletteName(forTagHex: hex) else { return nil }
        return tagPickerStoredHex(for: palette)
    }

    static func tagBackgroundColor(hex: String) -> Color {
        guard let palette = paletteName(forTagHex: hex) else {
            return Color(hex: hex)
        }

        return color(3, palette: palette)
    }

    func tagForegroundColor(hex: String) -> Color {
        guard let palette = Self.paletteName(forTagHex: hex) else {
            return highContrastText()
        }

        return Self.color(11, palette: palette)
    }

    private func paletteName(for _: BochiThemeRole) -> BochiThemePaletteName {
        palettes.main
    }

    private func accentPalette(for role: BochiThemeRole) -> BochiThemePaletteName {
        if let palette = palettes.accent.paletteName {
            return palette
        }

        switch role {
        case .task, .recurringTask:
            return .jade
        case .reward:
            return .tomato
        case .neutral, .settings:
            return palettes.main
        }
    }

    private func completedTaskCheckmarkPalette(hasPremiumAccess: Bool) -> BochiThemePaletteName {
        guard hasPremiumAccess else { return Self.premiumPalette }

        return palettes.accent.paletteName ?? .sky
    }

    private func taskRefundAmountPalette(hasPremiumAccess: Bool) -> BochiThemePaletteName {
        guard hasPremiumAccess else { return Self.premiumPalette }

        return accentPalette(for: .reward)
    }

    private func rewardRefundAmountPalette(hasPremiumAccess: Bool) -> BochiThemePaletteName {
        guard hasPremiumAccess else { return Self.premiumPalette }

        return .green
    }

    private func deletePalette() -> BochiThemePaletteName {
        palettes.accent.paletteName ?? .tomato
    }

    private static func role(for tab: AppTab) -> BochiThemeRole {
        switch tab {
        case .earn:
            return .task
        case .tasks:
            return .task
        case .recurringTasks:
            return .recurringTask
        case .rewards:
            return .reward
        case .spend:
            return .reward
        case .vault:
            return .reward
        case .settings:
            return .settings
        }
    }

    private static func paletteName(forTagHex hex: String) -> BochiThemePaletteName? {
        let normalizedHex = hex.lowercased()

        for palette in tagPickerPalettes {
            let radixPalette = radixPalette(named: palette)
            let matches = radixPalette.hex(11, colorScheme: .light) == normalizedHex
                || radixPalette.hex(11, colorScheme: .dark) == normalizedHex
                || radixPalette.hex(9, colorScheme: .light) == normalizedHex
                || radixPalette.hex(9, colorScheme: .dark) == normalizedHex
            if matches {
                return palette
            }
        }

        return nil
    }

    private static func radixPalette(named palette: BochiThemePaletteName) -> RadixPalette {
        switch palette {
        case .paper:
            return .paper
        case .cotton:
            return .cotton
        case .porcelain:
            return .porcelain
        case .ink:
            return .ink
        case .yellow:
            return .yellow
        case .amber:
            return .amber
        case .orange:
            return .orange
        case .tomato:
            return .tomato
        case .red:
            return .red
        case .ruby:
            return .ruby
        case .crimson:
            return .crimson
        case .pink:
            return .pink
        case .plum:
            return .plum
        case .purple:
            return .purple
        case .violet:
            return .violet
        case .iris:
            return .iris
        case .indigo:
            return .indigo
        case .blue:
            return .blue
        case .cyan:
            return .cyan
        case .teal:
            return .teal
        case .jade:
            return .jade
        case .green:
            return .green
        case .grass:
            return .grass
        case .lime:
            return .lime
        case .mint:
            return .mint
        case .sky:
            return .sky
        }
    }
}

private struct BochiThemeKey: EnvironmentKey {
    static let defaultValue = BochiTheme.default
}

extension EnvironmentValues {
    var bochiTheme: BochiTheme {
        get { self[BochiThemeKey.self] }
        set { self[BochiThemeKey.self] = newValue }
    }
}

extension View {
    func bochiTheme(_ theme: BochiTheme) -> some View {
        environment(\.bochiTheme, theme)
    }
}

private struct RadixPalette {
    let light: [String]
    let dark: [String]

    func color(_ step: Int) -> Color {
        Color(uiColor: uiColor(step))
    }

    func uiColor(_ step: Int) -> UIColor {
        let index = min(max(step, 1), 12) - 1

        return UIColor { traits in
            let scheme: UIUserInterfaceStyle = traits.userInterfaceStyle == .dark ? .dark : .light
            let hex = hex(index + 1, colorScheme: scheme)
            return UIColor(radixHex: hex)
        }
    }

    func hex(_ step: Int, colorScheme: UIUserInterfaceStyle) -> String {
        let index = min(max(step, 1), 12) - 1
        return colorScheme == .dark ? dark[index] : light[index]
    }
}

private extension RadixPalette {
    static let paper = RadixPalette(
        light: [
            "#fffdf8", "#fbf7ee", "#f4efe4", "#eee7da",
            "#e7dece", "#ded2bf", "#d2c4ad", "#bba98e",
            "#9e8a6e", "#927e64", "#6c5d4f", "#2e2923"
        ],
        dark: [
            "#15130f", "#1d1a15", "#29241c", "#342d23",
            "#413629", "#514331", "#66523b", "#82684a",
            "#a98c61", "#b79a6c", "#d6c29f", "#f5ecd9"
        ]
    )

    static let cotton = RadixPalette(
        light: [
            "#fffefd", "#fbfaf7", "#f4f2ee", "#eeebe6",
            "#e6e2dc", "#dbd5cd", "#cdc5ba", "#b6ab9e",
            "#8f8375", "#827668", "#62584f", "#24221f"
        ],
        dark: [
            "#121110", "#1a1917", "#24221f", "#2e2b27",
            "#39352f", "#474138", "#5a5145", "#74695a",
            "#9a8d78", "#aa9d87", "#cfc2ad", "#f7f1e7"
        ]
    )

    static let porcelain = RadixPalette(
        light: [
            "#fffefe", "#fbfbfa", "#f3f3f1", "#ecebea",
            "#e4e2df", "#d8d5d1", "#c9c4be", "#aea7a0",
            "#817a72", "#756e67", "#57524d", "#1f1f1d"
        ],
        dark: [
            "#111111", "#181817", "#22211f", "#2b2927",
            "#35322f", "#423e39", "#534d47", "#6c635b",
            "#8c8377", "#9c9387", "#c8c0b4", "#f4f0ea"
        ]
    )

    static let ink = RadixPalette(
        light: [
            "#ffffff", "#fbfbfb", "#f2f2f2", "#eaeaea",
            "#e2e2e1", "#d6d6d4", "#c8c8c5", "#aeaeaa",
            "#73736f", "#686864", "#50504d", "#181818"
        ],
        dark: [
            "#0f0f0f", "#171717", "#202020", "#292929",
            "#333332", "#3f3f3d", "#50504d", "#696965",
            "#80807b", "#8e8e89", "#c0c0ba", "#f2f2ee"
        ]
    )

    static let yellow = RadixPalette(
        light: [
            "#fefcf4", "#fefbef", "#fcf8e4", "#faf6d9",
            "#f8f3cc", "#f6efba", "#f3eaa4", "#ede281",
            "#decb1b", "#ccba14", "#7f7515", "#3e3b18"
        ],
        dark: [
            "#1f1c10", "#272410", "#353011", "#453f12",
            "#575013", "#6c6214", "#847816", "#a29418",
            "#decb1b", "#ebd833", "#eee381", "#f5f1cc"
        ]
    )

    static let amber = RadixPalette(
        light: [
            "#fefbf4", "#fefaef", "#fcf5e4", "#faf1d9",
            "#f8eccc", "#f5e5bb", "#f2dca5", "#ecce82",
            "#dca61e", "#ca9716", "#7f6115", "#3e3418"
        ],
        dark: [
            "#1f1a10", "#272010", "#352b11", "#453613",
            "#574414", "#6b5215", "#826417", "#a07a19",
            "#dca61e", "#eab634", "#eecf81", "#f5e9cc"
        ]
    )

    static let orange = RadixPalette(
        light: [
            "#fefaf4", "#fef8ef", "#fcf1e4", "#faebd9",
            "#f8e3cc", "#f5d9bb", "#f2cca5", "#ecb882",
            "#dc7d1e", "#ca7016", "#8c5217", "#3e2b18"
        ],
        dark: [
            "#1f1810", "#271d10", "#352411", "#452c13",
            "#573614", "#6b4115", "#824d17", "#a05d19",
            "#dc7d1e", "#ea8f34", "#eeb881", "#f5e0cc"
        ]
    )

    static let tomato = RadixPalette(
        light: [
            "#fef9f4", "#fef6f0", "#fcede5", "#fae4da",
            "#f8d9ce", "#f5cbbd", "#f1baa7", "#ec9d85",
            "#db4b24", "#ca411c", "#8c3017", "#3e2118"
        ],
        dark: [
            "#1f1610", "#271811", "#351c12", "#452114",
            "#562616", "#6a2b18", "#82321a", "#a03b1d",
            "#db4b24", "#e6623d", "#ee9981", "#f3d6cd"
        ]
    )

    static let red = RadixPalette(
        light: [
            "#fef9f4", "#fdf4f0", "#fceae6", "#fadfdb",
            "#f7d2cf", "#f4c1bf", "#f0abab", "#ea898a",
            "#d9262c", "#c81e23", "#8c171b", "#3e181a"
        ],
        dark: [
            "#1f1410", "#271512", "#341614", "#441816",
            "#561919", "#691b1c", "#811e1f", "#9e2023",
            "#d9262c", "#e43f45", "#ee8185", "#f3cecf"
        ]
    )

    static let ruby = RadixPalette(
        light: [
            "#fef9f5", "#fdf4f1", "#fbeae9", "#f9dfe0",
            "#f6d2d6", "#f2c1c9", "#eeacb8", "#e78a9d",
            "#d22850", "#c11f45", "#8b1833", "#3e1821"
        ],
        dark: [
            "#1e1412", "#261515", "#331619", "#42181f",
            "#531a24", "#661c2b", "#7d1f33", "#99223c",
            "#d22850", "#e13d63", "#ec839b", "#f2cfd7"
        ]
    )

    static let crimson = RadixPalette(
        light: [
            "#fef9f5", "#fdf4f3", "#fceaec", "#fadfe5",
            "#f7d2de", "#f4c1d3", "#f0abc6", "#ea89b1",
            "#d92674", "#c81e67", "#8c174a", "#3e1829"
        ],
        dark: [
            "#1f1414", "#271518", "#34161f", "#441827",
            "#561930", "#691b3a", "#811e46", "#9e2055",
            "#d92674", "#e43f86", "#ee81b0", "#f3cede"
        ]
    )

    static let pink = RadixPalette(
        light: [
            "#fef9f6", "#fdf5f4", "#fbeaef", "#f9e0eb",
            "#f7d4e5", "#f3c3dd", "#efaed4", "#e98dc4",
            "#d62e98", "#c9228c", "#8a1961", "#3e1830"
        ],
        dark: [
            "#1f1416", "#26151b", "#341725", "#431a30",
            "#551c3c", "#681f4a", "#7f225b", "#9c266f",
            "#d62e98", "#e147a8", "#ec83c5", "#f2cfe5"
        ]
    )

    static let plum = RadixPalette(
        light: [
            "#fef9f7", "#fdf5f6", "#faecf3", "#f7e2f1",
            "#f3d6ee", "#efc7ea", "#e9b3e4", "#df94dc",
            "#c43bc4", "#b530b5", "#7f247f", "#3e183e"
        ],
        dark: [
            "#1e1518", "#25171f", "#31192c", "#3f1d3b",
            "#4f204b", "#60245d", "#752973", "#902f8e",
            "#c43bc4", "#d251d2", "#e28de2", "#eed3ee"
        ]
    )

    static let purple = RadixPalette(
        light: [
            "#fdf9f7", "#fbf5f6", "#f6ecf4", "#f1e2f1",
            "#ecd6ef", "#e4c7eb", "#dab3e6", "#cb94df",
            "#9f3bc9", "#922ebd", "#652182", "#33183e"
        ],
        dark: [
            "#1c1518", "#211720", "#2b192d", "#361d3c",
            "#42204c", "#50245f", "#612975", "#752f91",
            "#9f3bc9", "#ae51d6", "#ca8be5", "#e6d2ef"
        ]
    )

    static let violet = RadixPalette(
        light: [
            "#fcf9f7", "#f9f5f6", "#f2ebf4", "#ebe2f2",
            "#e2d6f0", "#d7c6ed", "#c9b2e9", "#b293e3",
            "#7039d0", "#6329c7", "#441d86", "#26183e"
        ],
        dark: [
            "#1a1519", "#1d1620", "#24192e", "#2b1c3d",
            "#331f4f", "#3c2362", "#472879", "#552d96",
            "#7039d0", "#8450dc", "#ab87e8", "#dcd0f0"
        ]
    )

    static let iris = RadixPalette(
        light: [
            "#fbf9f7", "#f8f5f6", "#efebf4", "#e5e2f2",
            "#dad6f0", "#ccc6ed", "#b9b2e9", "#9c93e3",
            "#4839d0", "#3929c7", "#281d86", "#1c183e"
        ],
        dark: [
            "#181519", "#1a1620", "#1d192e", "#211c3d",
            "#261f4f", "#2b2362", "#312879", "#392d96",
            "#4839d0", "#5e50dc", "#9187e8", "#d4d0f0"
        ]
    )

    static let indigo = RadixPalette(
        light: [
            "#fbfaf7", "#f7f6f6", "#eceef4", "#e2e5f3",
            "#d5dbf0", "#c4ceed", "#b0bde9", "#8ea2e3",
            "#2e54d1", "#2549c1", "#1c3587", "#18213e"
        ],
        dark: [
            "#161619", "#171920", "#191d2e", "#1b233e",
            "#1d284f", "#202f62", "#23377a", "#264097",
            "#2e54d1", "#4669dd", "#869dea", "#d0d8f1"
        ]
    )

    static let blue = RadixPalette(
        light: [
            "#fbfbf7", "#f6f8f6", "#ebf2f4", "#e0ecf2",
            "#d3e4f0", "#c2daed", "#accee9", "#89bae2",
            "#2580d0", "#1d73bf", "#17568c", "#182d3e"
        ],
        dark: [
            "#161819", "#161d20", "#18242e", "#192d3d",
            "#1a374f", "#1c4262", "#1e4f79", "#205f96",
            "#2580d0", "#3692e2", "#81bbee", "#cee2f3"
        ]
    )

    static let cyan = RadixPalette(
        light: [
            "#fafbf7", "#f6faf6", "#ebf6f4", "#dff2f1",
            "#d2edee", "#c0e6ea", "#a9dee6", "#85d1de",
            "#1eabc8", "#169bb6", "#17798c", "#18383e"
        ],
        dark: [
            "#151b18", "#162120", "#162b2d", "#17383b",
            "#18454c", "#19555e", "#1a6775", "#1b7e90",
            "#1eabc8", "#24c5e5", "#81dcee", "#cdedf4"
        ]
    )

    static let teal = RadixPalette(
        light: [
            "#fafbf6", "#f6faf4", "#ebf5f0", "#dff1eb",
            "#d2ece5", "#c0e5de", "#a9ddd5", "#85d0c6",
            "#1ea99b", "#17978a", "#178c81", "#183e3b"
        ],
        dark: [
            "#151b16", "#16211c", "#162b25", "#173731",
            "#18453d", "#19544b", "#1a665c", "#1b7c71",
            "#1ea99b", "#1dcdbc", "#81eee3", "#cef3ef"
        ]
    )

    static let jade = RadixPalette(
        light: [
            "#fbfbf5", "#f6f9f3", "#ebf5ec", "#e1f0e6",
            "#d4ebde", "#c2e3d3", "#acdac6", "#8acbb1",
            "#26a174", "#1d9066", "#1d8660", "#183e30"
        ],
        dark: [
            "#161a14", "#172018", "#182a1f", "#193527",
            "#1b4230", "#1c503a", "#1e6146", "#217656",
            "#26a174", "#27c48a", "#87e8c5", "#d0f0e5"
        ]
    )

    static let green = RadixPalette(
        light: [
            "#fbfbf5", "#f6f9f1", "#ecf5e9", "#e1f0e1",
            "#d4ead7", "#c3e3ca", "#add9ba", "#8bca9f",
            "#289f54", "#1f8e48", "#1f8444", "#183e26"
        ],
        dark: [
            "#161a12", "#172015", "#18291a", "#1a351f",
            "#1b4126", "#1d4f2c", "#1f6035", "#22753f",
            "#289f54", "#29c261", "#88e7ab", "#d1f0dc"
        ]
    )

    static let grass = RadixPalette(
        light: [
            "#fbfbf4", "#f7f9f0", "#edf4e6", "#e2efdb",
            "#d6e9cf", "#c6e2bf", "#b2d8aa", "#91c88a",
            "#339b2c", "#2a8b23", "#298122", "#1b3e18"
        ],
        dark: [
            "#171a10", "#181f12", "#1a2914", "#1c3416",
            "#1f4018", "#224e1b", "#265e1f", "#2a7223",
            "#339b2c", "#37bd2e", "#91e48b", "#d4eed2"
        ]
    )

    static let lime = RadixPalette(
        light: [
            "#fcfcf4", "#fafaf0", "#f4f7e5", "#edf3da",
            "#e6efce", "#dce9bd", "#cfe2a8", "#bbd786",
            "#81b625", "#73a51d", "#577c18", "#303e18"
        ],
        dark: [
            "#1a1b10", "#1f2211", "#262d13", "#2f3a14",
            "#394916", "#435919", "#506d1b", "#61851f",
            "#81b625", "#98da25", "#c5eb84", "#e5f2cf"
        ]
    )

    static let mint = RadixPalette(
        light: [
            "#fbfcf6", "#f7faf4", "#ecf7ef", "#e1f3ea",
            "#d5efe4", "#c4e9dc", "#aee2d2", "#8cd7c3",
            "#2bb695", "#22a586", "#1d866d", "#183e36"
        ],
        dark: [
            "#161b16", "#17221b", "#182d24", "#1a3a2f",
            "#1c493b", "#1e5949", "#216d59", "#24856d",
            "#2bb695", "#2ed6af", "#87e8d1", "#d0f0e9"
        ]
    )

    static let sky = RadixPalette(
        light: [
            "#fbfbf7", "#f7faf7", "#ecf5f6", "#e2f1f4",
            "#d5ecf3", "#c4e5f0", "#afddee", "#8dcfe9",
            "#2ca8dd", "#1d9cd3", "#17698c", "#18333e"
        ],
        dark: [
            "#161a19", "#172022", "#192b30", "#1b3740",
            "#1d4453", "#1f5367", "#226580", "#257b9f",
            "#2ca8dd", "#46b7e7", "#81cdee", "#cde8f3"
        ]
    )

}

private extension UIColor {
    convenience init(radixHex: String) {
        let trimmed = radixHex.hasPrefix("#") ? String(radixHex.dropFirst()) : radixHex
        var rgbValue: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&rgbValue)

        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1
        )
    }
}
