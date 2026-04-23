import Foundation

// Generates random vibrant colors for tags. Port of the color generation
//
// Uses HSL color space to ensure colors are vibrant (not too pale or dark),
// then converts to hex. This is the same approach as CSS `hsl(h, s%, l%)`.
enum ColorGeneration {

    // Generates a random hex color string like "#3B82F6".
    // Hue: 0-360 (full color wheel)
    // Saturation: 70-90% (vibrant, not washed out)
    // Lightness: 45-60% (not too dark, not too light)
    static func randomHexColor() -> String {
        // Double.random(in:) is like Math.random() * (max - min) + min in JS.
        let h = Double.random(in: 0..<360)
        let s = Double.random(in: 0.70...0.90)
        let l = Double.random(in: 0.45...0.60)

        let (r, g, b) = hslToRGB(h: h, s: s, l: l)

        // String(format:) with %02X formats an Int as uppercase hex with zero-padding.
        // Like `.toString(16).padStart(2, '0').toUpperCase()` in JS.
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // Converts HSL values to RGB (0-255 per channel).
    //   h: hue in degrees (0-360)
    //   s: saturation (0.0-1.0)
    //   l: lightness (0.0-1.0)
    //
    // Standard HSL→RGB algorithm. In JS you'd use a library or CSS `hsl()`.
    // Swift has no built-in HSL support, so we implement the math directly.
    static func hslToRGB(h: Double, s: Double, l: Double) -> (r: Int, g: Int, b: Int) {
        // Achromatic case — no saturation means grayscale
        if s == 0 {
            let v = Int(round(l * 255))
            return (v, v, v)
        }

        let c = (1 - abs(2 * l - 1)) * s  // Chroma
        let hNorm = h / 60                  // Divide hue into 6 sectors
        let x = c * (1 - abs(hNorm.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2                   // Match lightness

        let (r1, g1, b1): (Double, Double, Double)
        switch Int(hNorm) % 6 {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }

        return (
            Int(round((r1 + m) * 255)),
            Int(round((g1 + m) * 255)),
            Int(round((b1 + m) * 255))
        )
    }
}
