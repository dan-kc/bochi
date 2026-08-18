import Foundation

// Chooses from the same paper color options the tag editor exposes, so a
// newly created tag always lands on a color the user can reselect later.
enum ColorGeneration {

    // Generates a random selectable paper hex color string like "#8c3017".
    static func randomHexColor() -> String {
        let palette = BochiTheme.tagPickerPalettes.randomElement() ?? .sky
        return BochiTheme.tagPickerStoredHex(for: palette)
    }
}
