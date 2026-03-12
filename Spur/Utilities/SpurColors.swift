import SwiftUI

enum SpurColors {
    static let background    = Color(hex: "0D0D0D")
    static let surface       = Color(hex: "141414")
    static let surfaceHover  = Color(hex: "1C1C1C")
    static let selectedCard  = Color(hex: "0A1F0E")
    static let accent        = Color(hex: "22C55E")
    static let textPrimary   = Color.white
    static let textSecondary = Color(hex: "9CA3AF")
    static let textMuted     = Color(hex: "4B5563")
    static let border        = Color(hex: "1F1F1F")
    static let portBadgeBg   = Color(hex: "0A2015")
    static let tagBg         = Color(hex: "1E1E1E")
    static let tagFg         = Color(hex: "6B7280")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
