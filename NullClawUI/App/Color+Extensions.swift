import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    init?(hex: String?) {
        guard let hex = hex else { return nil }
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&int) else { return nil }
        let a, r, g, b: UInt64
        switch hexString.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // MARK: - Contrast helpers

    /// Relative luminance of this color using the WCAG 2.x formula.
    /// Returns a value in [0, 1] where 0 = black, 1 = white.
    /// Falls back to 0.5 (unknown → use dark text) if the color cannot be resolved.
    var relativeLuminance: Double {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0.5 }
        func linearize(_ c: CGFloat) -> Double {
            let s = Double(c)
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
        #else
        return 0.5
        #endif
    }

    /// Returns `.white` or `.black` — whichever gives higher contrast against this background color.
    var contrastingForeground: Color {
        // WCAG contrast ratio: (L1 + 0.05) / (L2 + 0.05) where L1 >= L2.
        let lum = relativeLuminance
        let contrastWithWhite = (1.0 + 0.05) / (lum + 0.05)
        let contrastWithBlack = (lum + 0.05) / (0.0 + 0.05)
        return contrastWithWhite >= contrastWithBlack ? .white : .black
    }
}
