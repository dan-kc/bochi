import Foundation
import Testing
@testable import bochi

@MainActor
struct ColorGenerationTests {

    // Behaviour: When a tag is created, it receives a valid hex color string
    // from the same paper color options the user can select in the editor.
    @Test func randomColorHexReturnsValidFormat() {
        let color = ColorGeneration.randomHexColor()
        let pattern = /^#[0-9A-Fa-f]{6}$/
        let selectableColors = Set(BochiTheme.tagPickerPalettes.map(BochiTheme.tagPickerStoredHex))

        #expect(color.contains(pattern), "Color '\(color)' should match #RRGGBB format")
        #expect(selectableColors.contains(color), "Color '\(color)' should be a selectable paper tag color")
    }

    // Behaviour: When multiple tags are created, they rotate across the paper
    // options so the user can tell them apart at a glance.
    @Test func multipleCallsReturnDifferentColors() {
        var colors = Set<String>()
        for _ in 0..<10 {
            colors.insert(ColorGeneration.randomHexColor())
        }
        #expect(colors.count > 1, "Expected multiple unique colors, got \(colors.count)")
    }

}
