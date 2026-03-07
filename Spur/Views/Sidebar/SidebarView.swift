import SwiftUI

// TODO: [Phase 3] Implement SidebarView — see agents.md Prompt 6.
// Shows: selected repo info, experiment list, "New Experiment" button.

struct SidebarView: View {
    var body: some View {
        VStack {
            Text("Experiments")
                .font(.headline)
                .padding()
            ExperimentListView()
        }
        .frame(minWidth: 200)
    }
}
