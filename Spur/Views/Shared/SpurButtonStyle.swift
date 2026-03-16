import SwiftUI

/// Primary action button style using the photographer's grayscale accent.
/// Near-white text on a dark translucent fill in dark mode;
/// near-black text on a light translucent fill in light mode.
struct SpurButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(SpurColors.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(SpurColors.accentBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(SpurColors.accent.opacity(0.25), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
