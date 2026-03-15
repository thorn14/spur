import SwiftUI
import AppKit

/// Photographer's grayscale design system.
///
/// Custom backgrounds use NSColor dynamic providers so they adapt to light/dark
/// without following the system window-background defaults (which are too grey
/// for the high-contrast look we want).  Text, borders, and status colours lean
/// on macOS semantic colours so they respect Increase-Contrast accessibility
/// settings automatically.
enum SpurColors {

    // MARK: - Backgrounds (custom adaptive)

    /// Deep near-black in dark mode, warm near-white in light mode.
    static let background = adaptive(
        dark:  (0.04, 0.04, 0.04),
        light: (0.97, 0.97, 0.97)
    )

    /// Slightly elevated panel surface.
    static let surface = adaptive(
        dark:  (0.09, 0.09, 0.09),
        light: (1.00, 1.00, 1.00)
    )

    /// Hover state for interactive cards/rows.
    static let surfaceHover = adaptive(
        dark:  (0.13, 0.13, 0.13),
        light: (0.93, 0.93, 0.93)
    )

    /// Selected-card background (was green-tinted; now neutral charcoal/light-grey).
    static let selectedCard = adaptive(
        dark:  (0.18, 0.18, 0.18),
        light: (0.88, 0.88, 0.88)
    )

    /// Tag / badge chip background.
    static let tagBg = adaptive(
        dark:  (0.13, 0.13, 0.13),
        light: (0.91, 0.91, 0.91)
    )

    // MARK: - Accent (photographer neutral — near-white dark / near-black light)

    /// Primary action highlight and selected-state foreground.
    /// Replaces the previous green #22C55E with a max-contrast neutral.
    static let accent = adaptive(
        dark:  (0.92, 0.92, 0.92),
        light: (0.09, 0.09, 0.09)
    )

    /// Translucent accent background for badges and button fills.
    /// Uses a computed property so we can build the opacity variant from the same source.
    static var accentBackground: Color {
        adaptive(
            dark:  (0.92, 0.92, 0.92),
            light: (0.09, 0.09, 0.09)
        )
        .opacity(0.09)
    }

    // MARK: - Text (macOS semantic — adapts + honours Increase-Contrast)

    static let textPrimary   = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textMuted     = Color(nsColor: .tertiaryLabelColor)

    // MARK: - Structural (macOS semantic)

    /// Thin separator / border line.
    static let border = Color(nsColor: .separatorColor)

    /// Tag foreground text.
    static let tagFg  = Color(nsColor: .tertiaryLabelColor)

    // MARK: - Status (retain for accessibility)

    /// Running / active — high-contrast labelColor so it's readable in both modes.
    static let statusRunning = Color(nsColor: .labelColor)
    /// Idle — subdued.
    static let statusIdle    = Color(nsColor: .tertiaryLabelColor)
    /// Error — system red (WCAG AA on all our backgrounds).
    static let statusError   = Color(nsColor: .systemRed)
    /// Warning / detached — system orange.
    static let statusWarning = Color(nsColor: .systemOrange)

    // MARK: - Backward-compat aliases

    /// Alias kept so call-sites that used `portBadgeBg` continue to compile.
    static var portBadgeBg: Color { accentBackground }

    // MARK: - Private helper

    private static func adaptive(
        dark:  (CGFloat, CGFloat, CGFloat),
        light: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark,
                                                     .accessibilityHighContrastDarkAqua,
                                                     .accessibilityHighContrastVibrantDark]) != nil
            let (r, g, b) = isDark ? dark : light
            return NSColor(sRGBRed: r, green: g, blue: b, alpha: 1)
        })
    }
}

// MARK: - Hex colour convenience (kept for call-sites that still use it)

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
