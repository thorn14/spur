import SwiftUI

/// Root view: shows RepoPickerView until a repo is selected, then the main workspace.
struct ContentView: View {
    @EnvironmentObject var repoViewModel: RepoViewModel

    var body: some View {
        Group {
            if repoViewModel.isLoading {
                ProgressView("Loading…")
                    .frame(width: 300, height: 200)
            } else if repoViewModel.currentRepo == nil {
                RepoPickerView()
            } else {
                // TODO: [Phase 3] Replace with NavigationSplitView workspace
                Text("Repo: \(repoViewModel.currentRepo?.path ?? "")")
                    .padding()
                    .frame(minWidth: 600, minHeight: 400)
            }
        }
    }
}
