import SwiftUI

struct ThemeSettingsView: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @Environment(UserSettingsStore.self) private var userSettingsStore

    @State private var isPremiumUpsellPresented = false

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }

    private var displayedPalettes: BochiThemePalettePreferences {
        userSettingsStore.effectiveThemePalettes(hasPremiumAccess: hasPremiumAccess)
    }

    var body: some View {
        List {
            Section {
                mainPaletteMenu
                accentPaletteMenu
            } footer: {
                if !hasPremiumAccess {
                    Label("Themes are a Premium feature.", systemImage: "crown.fill")
                        .foregroundStyle(theme.premiumText())
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.appBackground())
        .foregroundStyle(theme.primaryText())
        .navigationTitle("Themes")
        .fullScreenCover(isPresented: $isPremiumUpsellPresented) {
            PremiumUpsellView()
        }
    }

    @ViewBuilder
    private var mainPaletteMenu: some View {
        if hasPremiumAccess {
            Menu {
                ForEach(BochiTheme.selectablePalettes, id: \.self) { palette in
                    Button {
                        setMainPalette(palette)
                    } label: {
                        if displayedPalettes.main == palette {
                            Label(palette.displayName, systemImage: "checkmark")
                        } else {
                            Text(palette.displayName)
                        }
                    }
                }
            } label: {
                mainPaletteLabel
            }
        } else {
            premiumLockedPaletteButton {
                mainPaletteLabel
            }
        }
    }

    @ViewBuilder
    private var accentPaletteMenu: some View {
        if hasPremiumAccess {
            Menu {
                Button {
                    setAccent(.semantic)
                } label: {
                    if displayedPalettes.accent == .semantic {
                        Label("Semantic", systemImage: "checkmark")
                    } else {
                        Text("Semantic")
                    }
                }

                ForEach(BochiTheme.selectablePalettes, id: \.self) { palette in
                    let accent = BochiThemeAccentChoice.palette(palette)
                    Button {
                        setAccent(accent)
                    } label: {
                        if displayedPalettes.accent == accent {
                            Label(palette.displayName, systemImage: "checkmark")
                        } else {
                            Text(palette.displayName)
                        }
                    }
                }
            } label: {
                accentPaletteLabel
            }
        } else {
            premiumLockedPaletteButton {
                accentPaletteLabel
            }
        }
    }

    private var mainPaletteLabel: some View {
        HStack {
            Label("Main", systemImage: "circle.grid.cross")
            Spacer()
            Text(displayedPalettes.main.displayName)
                .foregroundStyle(theme.secondaryText())
        }
    }

    private var accentPaletteLabel: some View {
        HStack {
            Label("Accent", systemImage: "paintbrush")
            Spacer()
            Text(displayedPalettes.accent.displayName)
                .foregroundStyle(theme.secondaryText())
        }
    }

    private func premiumLockedPaletteButton<LabelContent: View>(
        @ViewBuilder label: () -> LabelContent
    ) -> some View {
        Button {
            isPremiumUpsellPresented = true
        } label: {
            label()
                .environment(\.isEnabled, false)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setMainPalette(_ palette: BochiThemePaletteName) {
        guard hasPremiumAccess else { return }
        var palettes = userSettingsStore.themePalettes
        palettes.main = palette
        userSettingsStore.setThemePalettes(palettes)
    }

    private func setAccent(_ accent: BochiThemeAccentChoice) {
        guard hasPremiumAccess else { return }
        var palettes = userSettingsStore.themePalettes
        palettes.accent = accent
        userSettingsStore.setThemePalettes(palettes)
    }
}

#Preview {
    ThemeSettingsView()
        .environment(AuthManager(
            apiClient: AppConfiguration.makeAuthAPIClient(),
            tokenStorage: KeychainTokenStorage(),
            appleEntitlementClient: StoreKitAppleEntitlementClient()
        ))
        .environment(PremiumAccessStore())
        .environment(UserSettingsStore())
}
