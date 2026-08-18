import Testing
import UIKit
@testable import bochi

@MainActor
struct ThemeResolutionTests {
    // Behaviour: choosing a main palette recolors ordinary entity surfaces
    // without reviving the old task/recurringTask/reward theme split.
    @Test func mainPaletteDrivesRoleColors() {
        let theme = BochiTheme(palettes: BochiThemePalettePreferences(
            main: .mint,
            accent: .palette(.sky)
        ))

        #expect(lightHex(theme.uiColor(1, role: .task)) == lightHex(BochiTheme.uiColor(1, palette: .mint)))
        #expect(lightHex(theme.uiColor(9, role: .reward)) == lightHex(BochiTheme.uiColor(9, palette: .mint)))
    }

    // Behaviour: semantic accent keeps earn actions green and spend/delete
    // actions tomato, regardless of the selected main palette.
    @Test func semanticAccentUsesEntityMeaning() {
        let theme = BochiTheme(palettes: BochiThemePalettePreferences(
            main: .ink,
            accent: .semantic
        ))

        #expect(lightHex(theme.accentUIColor(9, for: .task)) == lightHex(BochiTheme.uiColor(9, palette: .jade)))
        #expect(lightHex(theme.accentUIColor(9, for: .recurringTask)) == lightHex(BochiTheme.uiColor(9, palette: .jade)))
        #expect(lightHex(theme.accentUIColor(9, for: .reward)) == lightHex(BochiTheme.uiColor(9, palette: .tomato)))
    }

    // Behaviour: choosing a palette accent makes every entity action use that
    // same accent instead of semantic earn/spend colors.
    @Test func paletteAccentOverridesSemanticEntityColors() {
        let theme = BochiTheme(palettes: BochiThemePalettePreferences(
            main: .ink,
            accent: .palette(.sky)
        ))

        #expect(lightHex(theme.accentUIColor(9, for: .task)) == lightHex(BochiTheme.uiColor(9, palette: .sky)))
        #expect(lightHex(theme.accentUIColor(9, for: .reward)) == lightHex(BochiTheme.uiColor(9, palette: .sky)))
    }

    // Behaviour: the completed-task checkmark uses premium color as an upsell
    // cue for free users, but follows the user's accent once premium is active.
    @Test func completedTaskCheckmarkUsesPremiumOrAccentColor() {
        let semanticTheme = BochiTheme(palettes: BochiThemePalettePreferences(
            main: .ink,
            accent: .semantic
        ))

        #expect(lightHex(semanticTheme.completedTaskCheckmarkUIColor(hasPremiumAccess: false)) == lightHex(BochiTheme.uiColor(9, palette: .violet)))
        #expect(lightHex(semanticTheme.completedTaskCheckmarkUIColor(hasPremiumAccess: true)) == lightHex(BochiTheme.uiColor(9, palette: .sky)))

        let paletteAccentTheme = BochiTheme(palettes: BochiThemePalettePreferences(
            main: .ink,
            accent: .palette(.mint)
        ))

        #expect(lightHex(paletteAccentTheme.completedTaskCheckmarkUIColor(hasPremiumAccess: true)) == lightHex(BochiTheme.uiColor(9, palette: .mint)))
    }

    // Behaviour: the list refund amount is a premium upsell color for free
    // users, but acts like a reward spend button once refunds are available.
    @Test func taskRefundAmountUsesPremiumOrRewardSpendColor() {
        let semanticTheme = BochiTheme(palettes: BochiThemePalettePreferences(
            main: .ink,
            accent: .semantic
        ))

        #expect(lightHex(semanticTheme.taskRefundAmountUIColor(hasPremiumAccess: false)) == lightHex(BochiTheme.uiColor(9, palette: .violet)))
        #expect(lightHex(semanticTheme.taskRefundAmountUIColor(hasPremiumAccess: true)) == lightHex(BochiTheme.uiColor(9, palette: .tomato)))

        let paletteAccentTheme = BochiTheme(palettes: BochiThemePalettePreferences(
            main: .ink,
            accent: .palette(.mint)
        ))

        #expect(lightHex(paletteAccentTheme.taskRefundAmountUIColor(hasPremiumAccess: true)) == lightHex(BochiTheme.uiColor(9, palette: .mint)))
    }

    // Behaviour: refunding a completed reward gives points back, so premium
    // users see the positive semantic color while free users see the upsell cue.
    @Test func rewardRefundAmountUsesPremiumOrPositiveColor() {
        let semanticTheme = BochiTheme(palettes: BochiThemePalettePreferences(
            main: .ink,
            accent: .semantic
        ))

        #expect(lightHex(semanticTheme.rewardRefundAmountUIColor(hasPremiumAccess: false)) == lightHex(BochiTheme.uiColor(9, palette: .violet)))
        #expect(lightHex(semanticTheme.rewardRefundAmountUIColor(hasPremiumAccess: true)) == lightHex(BochiTheme.uiColor(9, palette: .green)))

        let paletteAccentTheme = BochiTheme(palettes: BochiThemePalettePreferences(
            main: .ink,
            accent: .palette(.mint)
        ))

        #expect(lightHex(paletteAccentTheme.rewardRefundAmountUIColor(hasPremiumAccess: true)) == lightHex(BochiTheme.uiColor(9, palette: .green)))
    }

    // Behaviour: arbitrary tag colors from outside the picker do not become a
    // selected option in the tag color editor.
    @Test func arbitraryTagColorsAreNotSelectablePickerOptions() {
        #expect(BochiTheme.normalizedTagPickerStoredHex(for: "#336699") == nil)
    }

    // Behaviour: tag color picker previews expose fixed light and dark swatches
    // so the picker shows both appearances regardless of the active UI mode.
    @Test func tagPickerPreviewColorsIncludeFixedLightAndDarkVariants() {
        let lightPreview = BochiTheme.tagPickerPreviewColors(for: .red, colorScheme: .light)
        let darkPreview = BochiTheme.tagPickerPreviewColors(for: .red, colorScheme: .dark)

        #expect(lightPreview.backgroundHex.lowercased() == resolvedHex(BochiTheme.uiColor(3, palette: .red), colorScheme: .light).lowercased())
        #expect(darkPreview.backgroundHex.lowercased() == resolvedHex(BochiTheme.uiColor(3, palette: .red), colorScheme: .dark).lowercased())
        #expect(lightPreview.backgroundHex != darkPreview.backgroundHex)
    }

    private func lightHex(_ color: UIColor) -> String {
        resolvedHex(color, colorScheme: .light)
    }

    private func resolvedHex(_ color: UIColor, colorScheme: UIUserInterfaceStyle) -> String {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: colorScheme))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}
