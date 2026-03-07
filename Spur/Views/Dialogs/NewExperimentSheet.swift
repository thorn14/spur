import SwiftUI

// TODO: [Phase 3] Implement NewExperimentSheet — see agents.md Prompt 6.

struct NewExperimentSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("New Experiment")
                .font(.headline)
            Text("TODO: Name input + create action")
                .foregroundColor(.secondary)
            Button("Cancel") { dismiss() }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 160)
    }
}
