import SwiftUI

// TODO: [Phase 3] Implement NewOptionSheet — name input, source selector (from main / from checkpoint).
// Calls GitService.createBranchAndWorktree and persists. See agents.md Prompt 6.

struct NewOptionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("New Option")
                .font(.headline)
            Text("TODO: Name input, source selector, create action")
                .foregroundColor(.secondary)
            Button("Cancel") { dismiss() }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 200)
    }
}
