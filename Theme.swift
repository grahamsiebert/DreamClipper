import SwiftUI

struct Theme {
    // Screen Studio-inspired dark theme
    static let background = Color(hex: "0D0D0F")      // Near-black background
    static let surface = Color(hex: "1A1A1E")         // Elevated surface (panels/cards)
    static let surfaceHover = Color(hex: "252529")    // Hover state
    static let surfaceSecondary = Color(hex: "141416") // Secondary surface (timeline background)

    static let accent = Color(hex: "5856D6")          // Purple accent
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "5856D6"), Color(hex: "7A78FF")],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let text = Color.white
    static let textSecondary = Color(hex: "8E8E93")   // Muted gray text
    static let textTertiary = Color(hex: "636366")    // Even more muted

    static let border = Color.white.opacity(0.06)     // Very subtle borders
    static let borderLight = Color.white.opacity(0.1) // Slightly more visible

    // Size status colors
    static let sizeGood = Color(hex: "34C759")        // Green - under 10MB
    static let sizeWarning = Color(hex: "FF9500")     // Orange - 10-15MB
    static let sizeDanger = Color(hex: "FF3B30")      // Red - over 15MB

    // Consistent corner radius values
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
    static let cornerRadiusXL: CGFloat = 20

    // Shadow presets for depth
    static func cardShadow() -> some View {
        Color.black.opacity(0.4)
    }

    static let shadowRadius: CGFloat = 24
    static let shadowY: CGFloat = 8
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
