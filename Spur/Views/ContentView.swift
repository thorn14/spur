import SwiftUI

/// Root view: shows RepoPickerView until a repo is selected, then the full workspace.
struct ContentView: View {
    @EnvironmentObject var repoViewModel: RepoViewModel
    @EnvironmentObject var experimentViewModel: ExperimentViewModel
    @EnvironmentObject var optionViewModel: OptionViewModel

    var body: some View {
        Group {
            if repoViewModel.isLoading {
                ProgressView("Loading…")
                    .frame(width: 300, height: 200)
            } else if repoViewModel.currentRepo == nil {
                RepoPickerView()
            } else {
                WorkspaceView()
            }
        }
    }
}

// MARK: - WorkspaceView

/// The main three-column workspace: sidebar (experiments) | detail (option tabs + content).
private struct WorkspaceView: View {
    @EnvironmentObject var experimentViewModel: ExperimentViewModel
    @EnvironmentObject var optionViewModel: OptionViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                OptionTabBar()
                Divider()
                OptionDetailView()
            }
        }
        // When the selected experiment changes, tell OptionViewModel to filter its options.
        .onChange(of: experimentViewModel.selectedExperimentId) { _ in
            optionViewModel.setExperiment(experimentViewModel.selectedExperiment)
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
