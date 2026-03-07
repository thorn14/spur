import SwiftUI

struct OptionDetailView: View {
    @EnvironmentObject var optionViewModel: OptionViewModel

    var body: some View {
        if let option = optionViewModel.selectedOption {
            // .id resets WebViewStore + scroll state when switching options
            OptionWorkspaceView(option: option)
                .id(option.id)
        } else {
            EmptyOptionView()
        }
    }
}

// MARK: - Option workspace (Phase 4 + 6)

private struct OptionWorkspaceView: View {
    let option: SpurOption
    @EnvironmentObject var optionViewModel: OptionViewModel
    @StateObject private var webViewStore = WebViewStore()
    @State private var bottomTab: BottomTab = .logs
    @State private var showCreatePR = false

    private enum BottomTab: String, CaseIterable {
        case logs = "Logs"
        case terminal = "Terminal"
    }

    private var localURL: URL {
        URL(string: "http://localhost:\(option.port)") ?? URL(string: "about:blank")!
    }

    private var isRunning: Bool {
        optionViewModel.isServerRunning(option.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Control bar ──────────────────────────────────────────────
            HStack(spacing: 8) {
                // Option name + branch
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(.headline)
                    Text(option.branchName)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Port badge
                Text(":\(option.port)")
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                // Status badge
                StatusBadge(status: option.status)

                Divider().frame(height: 18)

                // Reload preview
                Button {
                    webViewStore.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload preview")
                .disabled(!isRunning)

                // Open in browser
                Button {
                    NSWorkspace.shared.open(localURL)
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.plain)
                .help("Open in browser")
                .disabled(!isRunning)

                // Open in Terminal
                Button {
                    optionViewModel.openInTerminal()
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.plain)
                .help("Open worktree in Terminal")

                Divider().frame(height: 18)

                // Create PR
                Button {
                    showCreatePR = true
                } label: {
                    Image(systemName: "arrow.triangle.pull")
                }
                .buttonStyle(.plain)
                .help("Create Pull Request")

                Divider().frame(height: 18)

                // Start / Stop
                if isRunning {
                    Button("Stop") {
                        Task { await optionViewModel.stopServer() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button("Start") {
                        optionViewModel.startServer()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // ── Preview + Bottom panel | Turns panel ────────────────────
            HSplitView {
                // Left: preview + logs/terminal
                VSplitView {
                    // Top: live web preview
                    Group {
                        if isRunning {
                            WebPreviewView(url: localURL, store: webViewStore)
                        } else {
                            ServerOffPlaceholder(port: option.port)
                        }
                    }
                    .frame(minHeight: 120)

                    // Bottom: tabbed logs / terminal
                    VStack(spacing: 0) {
                        // Tab bar
                        HStack {
                            Picker("", selection: $bottomTab) {
                                ForEach(BottomTab.allCases, id: \.self) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            Spacer()
                        }
                        .background(Color(NSColor.controlBackgroundColor))

                        Divider()

                        switch bottomTab {
                        case .logs:
                            LogOutputView(lines: optionViewModel.currentLogs)
                        case .terminal:
                            CommandRunnerView(worktreePath: option.worktreePath)
                        }
                    }
                    .frame(minHeight: 80)
                }
                .frame(minWidth: 300)

                // Right: turns panel
                TurnListView()
                    .frame(minWidth: 220, maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCreatePR) {
            CreatePRSheet(option: option)
        }
    }
}

// MARK: - Server-off placeholder

private struct ServerOffPlaceholder: View {
    let port: Int

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.circle")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Dev server is not running")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Press Start to launch the server at http://localhost:\(port)")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Empty state

private struct EmptyOptionView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No option selected")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Create or select an option from the tab bar above.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status badge

private struct StatusBadge: View {
    let status: OptionStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption).fontWeight(.medium)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var color: Color {
        switch status {
        case .idle:     return .secondary
        case .running:  return .green
        case .detached: return .orange
        case .error:    return .red
        }
    }
}
