import SwiftUI

struct GreenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(SpurColors.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(SpurColors.portBadgeBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(SpurColors.accent.opacity(0.3), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
