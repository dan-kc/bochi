import Foundation
import Testing
@testable import tofustash

struct ColorGenerationTests {

    @Test func randomColorHexReturnsValidFormat() {
        // Should match #RRGGBB pattern — like /^#[0-9A-Fa-f]{6}$/ in JS
        let color = ColorGeneration.randomHexColor()
        let pattern = /^#[0-9A-Fa-f]{6}$/
        #expect(color.contains(pattern), "Color '\(color)' should match #RRGGBB format")
    }

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

    @Test func hslToRGBRedAtZeroDegrees() {
        // Pure red: H=0, S=1.0, L=0.5 → RGB(255, 0, 0)
        let (r, g, b) = ColorGeneration.hslToRGB(h: 0, s: 1.0, l: 0.5)
        #expect(r == 255)
        #expect(g == 0)
        #expect(b == 0)
    }

    @Test func hslToRGBGreenAt120Degrees() {
        // Pure green: H=120, S=1.0, L=0.5 → RGB(0, 255, 0)
        let (r, g, b) = ColorGeneration.hslToRGB(h: 120, s: 1.0, l: 0.5)
        #expect(r == 0)
        #expect(g == 255)
        #expect(b == 0)
    }

    @Test func hslToRGBBlueAt240Degrees() {
        // Pure blue: H=240, S=1.0, L=0.5 → RGB(0, 0, 255)
        let (r, g, b) = ColorGeneration.hslToRGB(h: 240, s: 1.0, l: 0.5)
        #expect(r == 0)
        #expect(g == 0)
        #expect(b == 255)
    }

    @Test func hslToRGBWhite() {
        // White: any H, S=0, L=1.0 → RGB(255, 255, 255)
        let (r, g, b) = ColorGeneration.hslToRGB(h: 0, s: 0, l: 1.0)
        #expect(r == 255)
        #expect(g == 255)
        #expect(b == 255)
    }

    @Test func hslToRGBBlack() {
        // Black: any H, S=0, L=0 → RGB(0, 0, 0)
        let (r, g, b) = ColorGeneration.hslToRGB(h: 0, s: 0, l: 0)
        #expect(r == 0)
        #expect(g == 0)
        #expect(b == 0)
    }
}
