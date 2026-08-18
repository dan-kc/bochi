import Foundation
import Testing
@testable import bochi

@MainActor
struct UserSettingsStoreTests {
    private func makeSUT() -> UserSettingsStore {
        let suiteName = "bochi-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserSettingsStore(storageURL: TestHelpers.makeTemporaryFileURL("settings"), userDefaults: defaults)
    }

    // Behaviour: new users should see the free default theme: porcelain main
    // surfaces with semantic entity accents.
    @Test("Default theme palettes use free defaults")
    func defaultThemePalettesUseFreeDefaults() {
        let sut = makeSUT()

        #expect(sut.themePalettes == .default)
        #expect(sut.themePalettes.main == .porcelain)
        #expect(sut.themePalettes.accent == .semantic)
    }

    // Behaviour: premium users can personalize the main and accent palettes,
    // and those choices should reload when the app restarts.
    @Test("Theme palettes persist per owner")
    func themePalettesPersistPerOwner() {
        let storageURL = TestHelpers.makeTemporaryFileURL("settings-themes")
        let sut = UserSettingsStore(storageURL: storageURL, initialOwnerID: "user-a")

        let custom = BochiThemePalettePreferences(
            main: .mint,
            accent: .palette(.sky)
        )
        sut.setThemePalettes(custom)

        let reloaded = UserSettingsStore(storageURL: storageURL, initialOwnerID: "user-a")
        #expect(reloaded.themePalettes == custom)

        reloaded.setCurrentOwner("user-b")
        #expect(reloaded.themePalettes == .default)
    }

    // Behaviour: the theme palettes should be selectable, persist locally, and
    // remain ordered from paper-like neutrals into saturated accent options.
    @Test("Theme palettes are selectable and persistent")
    func themePalettesAreSelectableAndPersistent() {
        let storageURL = TestHelpers.makeTemporaryFileURL("settings-neutral-ui-themes")
        let sut = UserSettingsStore(storageURL: storageURL, initialOwnerID: "user-a")
        let custom = BochiThemePalettePreferences(
            main: .cotton,
            accent: .palette(.ink)
        )

        sut.setThemePalettes(custom)

        let reloaded = UserSettingsStore(storageURL: storageURL, initialOwnerID: "user-a")
        #expect(reloaded.themePalettes == custom)
        #expect(BochiTheme.selectablePalettes.prefix(4) == [
            .paper,
            .cotton,
            .porcelain,
            .ink
        ])
    }

    // Behaviour: lapsed users keep saved theme choices, but the visible app
    // theme falls back to the defaults until premium access returns.
    @Test("Effective theme palettes fall back while premium is lapsed")
    func effectiveThemePalettesFallBackWhilePremiumIsLapsed() {
        let sut = makeSUT()
        let custom = BochiThemePalettePreferences(
            main: .mint,
            accent: .palette(.sky)
        )

        sut.setThemePalettes(custom)

        #expect(sut.themePalettes == custom)
        #expect(sut.effectiveThemePalettes(hasPremiumAccess: true) == custom)
        #expect(sut.effectiveThemePalettes(hasPremiumAccess: false) == .default)
        #expect(sut.themePalettes == custom)
    }

    // Behaviour: if an old or corrupted local value is not a theme palette, the
    // app should render the default palette instead of reviving legacy colors.
    @Test("Invalid stored theme palette values fall back to defaults")
    func invalidStoredThemePaletteValuesFallBackToDefaults() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("settings-invalid-themes")
        let sut = UserSettingsStore(storageURL: storageURL, initialOwnerID: "user-a")

        try AppDatabase.shared.execute(
            """
            INSERT INTO user_settings (
                owner_id,
                theme_palette_main,
                theme_palette_accent
            )
            VALUES (?, ?, ?)
            ON CONFLICT(owner_id) DO UPDATE SET
                theme_palette_main = excluded.theme_palette_main,
                theme_palette_accent = excluded.theme_palette_accent
            """,
            bindings: [
                .text("user-a"),
                .text("mint"),
                .text("legacyBlue")
            ],
            at: storageURL
        )

        sut.setCurrentOwner("user-a")

        #expect(sut.themePalettes.main == .mint)
        #expect(sut.themePalettes.accent == .semantic)
    }

    // Behaviour: entity rows show their detail pills for new installs unless
    // this device explicitly opts out.
    @Test("Entity row detail setting defaults on")
    func entityRowDetailSettingDefaultsOn() {
        let sut = makeSUT()

        #expect(sut.showsEntityRowDetails == true)
    }

    // Behaviour: the row detail setting is a local device preference, so it
    // persists outside the synced owner-scoped settings table.
    @Test("Entity row detail setting persists local overrides")
    func entityRowDetailSettingPersistsLocalOverrides() {
        let suiteName = "bochi-row-display-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let storageURL = TestHelpers.makeTemporaryFileURL("settings-row-display")
        let sut = UserSettingsStore(storageURL: storageURL, initialOwnerID: "user-a", userDefaults: defaults)
        sut.setShowsEntityRowDetails(false)

        let reloaded = UserSettingsStore(storageURL: storageURL, initialOwnerID: "user-b", userDefaults: defaults)

        #expect(reloaded.showsEntityRowDetails == false)
    }

    // Behaviour: changing the row detail setting should never enqueue sync or
    // create owner-scoped settings because it is only a device display choice.
    @Test("Entity row detail setting is not synced")
    func entityRowDetailSettingIsNotSynced() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("settings-row-display-local-only")
        let sut = UserSettingsStore(storageURL: storageURL, initialOwnerID: "user-a")

        sut.setShowsEntityRowDetails(false)

        let settingsRowCount = try AppDatabase.shared.queryOne(
            "SELECT COUNT(*) FROM user_settings",
            at: storageURL
        ) { row in
            SQLiteColumn.int(row, index: 0)
        }
        let dirtyState = SyncStateStore(storageURL: storageURL).state(for: "user-a").dirty

        #expect(settingsRowCount == 0)
        #expect(dirtyState == SyncStateStore.DirtyState())
    }
}
