import SwiftUI

// TODO: [Phase 6] Implement CreatePRSheet — title + body + create action.
// See agents.md Prompt 9.

struct CreatePRSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Pull Request")
                .font(.headline)
            Text("TODO: Title, body inputs + create action")
                .foregroundColor(.secondary)
            Button("Cancel") { dismiss() }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 240)
    }
}
