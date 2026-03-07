import SwiftUI

// TODO: [Phase 5] Implement ForkFromCheckpointSheet — see agents.md Prompt 8.
// Name input → GitService.createBranchAndWorktree(from: .commit(turn.endCommit)).

struct ForkFromCheckpointSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Fork from Checkpoint")
                .font(.headline)
            Text("TODO: Turn picker + name input + fork action")
                .foregroundColor(.secondary)
            Button("Cancel") { dismiss() }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 200)
    }
}
