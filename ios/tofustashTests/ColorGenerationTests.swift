import Foundation
import Testing
@testable import tofustash

struct ColorGenerationTests {

    // Behaviour: When a tag is created, it receives a valid hex color string
    // that can be rendered by SwiftUI (format: #RRGGBB).
    @Test func randomColorHexReturnsValidFormat() {
        // Should match #RRGGBB pattern — like /^#[0-9A-Fa-f]{6}$/ in JS
        let color = ColorGeneration.randomHexColor()
        let pattern = /^#[0-9A-Fa-f]{6}$/
        #expect(color.contains(pattern), "Color '\(color)' should match #RRGGBB format")
    }

    // Behaviour: When multiple tags are created, they get visually distinct colors
    // so the user can tell them apart at a glance.
    @Test func multipleCallsReturnDifferentColors() {
        // Generate 10 colors — expect at least 2 unique values.
        // (Technically possible to fail if random produces the same color
        // 10 times, but astronomically unlikely with the HSL range.)
        var colors = Set<String>()
        for _ in 0..<10 {
            colors.insert(ColorGeneration.randomHexColor())
        }
        #expect(colors.count > 1, "Expected multiple unique colors, got \(colors.count)")
    }

}
