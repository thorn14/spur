import SwiftUI

struct RightPanelView: View {
    @EnvironmentObject var optionViewModel: OptionViewModel

    enum PanelTab: String, CaseIterable {
        case terminal = "Terminal"
        case logs     = "Logs"
        case git      = "Git"

        var icon: String {
            switch self {
            case .terminal: return "terminal"
            case .logs:     return "list.bullet.rectangle"
            case .git:      return "arrow.triangle.branch"
            }
        }
    }

    @State private var selectedTab: PanelTab = .terminal

    private var option: SpurOption? { optionViewModel.selectedOption }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(PanelTab.allCases, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon).font(.system(size: 11))
                            Text(tab.rawValue).font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(selectedTab == tab ? SpurColors.textPrimary : SpurColors.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle().fill(SpurColors.textPrimary).frame(height: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let option {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(option.status == .running ? SpurColors.statusRunning : SpurColors.statusIdle)
                            .frame(width: 6, height: 6)
                        Text(option.name)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(SpurColors.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                }
            }
            .background(.bar)

            Rectangle().fill(SpurColors.border).frame(height: 1)

            Group {
                switch selectedTab {
                case .terminal:
                    if let option {
                        SpurTerminalView(worktreePath: option.worktreePath)
                    } else {
                        noSelectionView("Select a worktree to open a terminal")
                    }
                case .logs:
                    ServerLogsView(logs: optionViewModel.currentLogs)
                case .git:
                    TurnListView().environmentObject(optionViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SpurColors.background)
        }
        .background(.ultraThinMaterial)
        .overlay(FilmGrainOverlay())
    }

    private func noSelectionView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left").font(.system(size: 24)).foregroundColor(SpurColors.textMuted)
            Text(message).font(.system(size: 12)).foregroundColor(SpurColors.textMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Server logs tab

struct ServerLogsView: View {
    let logs: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if logs.isEmpty {
                        Text("No server logs yet. Start the dev server to see output.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(SpurColors.textMuted)
                            .padding(10)
                    } else {
                        ForEach(logs.indices, id: \.self) { i in
                            Text(logs[i])
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(logLineColor(logs[i]))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                }
                .padding(10)
            }
            .background(SpurColors.background)
            .onChange(of: logs.count) { _ in
                if let last = logs.indices.last { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private func logLineColor(_ line: String) -> Color {
        if line.hasPrefix("[spur]") { return SpurColors.textMuted }
        if line.contains("error") || line.contains("Error") || line.hasPrefix("[stderr]") { return SpurColors.statusError }
        return SpurColors.textSecondary
    }
}

// MARK: - Inline terminal (user shell)

struct InlineTerminalView: View {
    let worktreePath: String
    @ObservedObject var viewModel: CommandRunnerViewModel

    @State private var commandText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Colored terminal output
            TerminalTextView(attributedText: viewModel.attributedOutput)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            // Input bar — always visible at the bottom, outside the scroll view
            Rectangle().fill(SpurColors.border).frame(height: 1)
            HStack(spacing: 0) {
                Text("$ ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(SpurColors.textPrimary)
                TextField("", text: $commandText)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                    .foregroundColor(SpurColors.textPrimary)
                    .focused($inputFocused)
                    .onSubmit { submit() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: NSColor(white: 0.08, alpha: 1)))
        }
        .onAppear {
            viewModel.startIfNeeded(worktreePath: worktreePath)
            inputFocused = true
        }
        .onChange(of: worktreePath) { newPath in
            viewModel.startIfNeeded(worktreePath: newPath)
        }
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = true }
    }

    private func submit() {
        let cmd = commandText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        commandText = ""
        viewModel.send(cmd)
        DispatchQueue.main.async { inputFocused = true }
    }
}
