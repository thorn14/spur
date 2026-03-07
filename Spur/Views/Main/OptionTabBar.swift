import SwiftUI

// TODO: [Phase 3] Implement OptionTabBar — horizontal tab strip for Options.
// See agents.md Prompt 6.

struct OptionTabBar: View {
    var body: some View {
        HStack {
            Text("No options")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
