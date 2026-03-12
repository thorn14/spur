import SwiftUI

/// Root view: shows RepoPickerView until a repo is selected, then the full workspace.
struct ContentView: View {
    @EnvironmentObject var repoViewModel: RepoViewModel
    @EnvironmentObject var prototypeViewModel: PrototypeViewModel
    @EnvironmentObject var optionViewModel: OptionViewModel

    var body: some View {
        Group {
            if repoViewModel.isLoading {
                loadingView
            } else if repoViewModel.currentRepo == nil {
                RepoPickerView()
                    .preferredColorScheme(.dark)
            } else {
                WorkspaceView()
                    .preferredColorScheme(.dark)
                    .sheet(isPresented: Binding(
                        get: { repoViewModel.appState?.needsSetup ?? false },
                        set: { _ in }
                    )) {
                        if let path = repoViewModel.currentRepo?.path {
                            RepoSetupSheet(repoPath: path)
                        }
                    }
            }
        }
    }

    private var loadingView: some View {
        ZStack {
            SpurColors.background.ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(SpurColors.accent)
                Text("Loading…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(SpurColors.textMuted)
            }
        }
        .preferredColorScheme(.dark)
        .frame(width: 300, height: 200)
    }
}

// MARK: - WorkspaceView

/// The main three-column workspace: worktree sidebar | web preview | terminal/logs/git panel.
private struct WorkspaceView: View {
    @EnvironmentObject var prototypeViewModel: PrototypeViewModel
    @EnvironmentObject var optionViewModel: OptionViewModel

    @State private var rightPanelWidth: CGFloat = 340

    var body: some View {
        HStack(spacing: 0) {
            // Left: worktree card sidebar
            WorktreeSidebarView()

            Rectangle().fill(SpurColors.border).frame(width: 1)

            // Center: web preview
            OptionDetailView()
                .frame(maxWidth: .infinity)

            Rectangle().fill(SpurColors.border).frame(width: 1)

            // Drag handle to resize right panel
            Color.clear
                .frame(width: 4)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let newWidth = rightPanelWidth - value.translation.width
                            rightPanelWidth = max(260, min(600, newWidth))
                        }
                )

            // Right: terminal/logs/git
            RightPanelView()
                .frame(width: rightPanelWidth)
        }
        .background(SpurColors.background)
        .frame(minWidth: 1000, minHeight: 600)
        .onChange(of: prototypeViewModel.selectedPrototypeId) { _ in
            optionViewModel.setPrototype(prototypeViewModel.selectedPrototype)
        }
    }
}
