import SwiftUI

// Adds a hex-string initializer to SwiftUI's Color type.
//
// Extensions are like adding methods to an existing class's prototype in JS,
// but type-safe — the compiler checks everything. You can't add stored
// properties, only computed ones and methods.
//
// Usage: Color(hex: "#3B82F6") or Color(hex: "3B82F6")
extension Color {
    init(hex: String) {
        // Strip the "#" prefix if present
        let hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex

        // Parse the hex string into RGB components (0-255 each).
        // UInt64 is like BigInt in JS — needed for Scanner's hex parsing API.
        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)

        // Extract R, G, B using bit shifting — same as in JS:
        //   const r = (0xFF0000 & hexNum) >> 16
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
