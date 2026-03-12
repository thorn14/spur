import SwiftUI

struct OptionDetailView: View {
    @EnvironmentObject var optionViewModel: OptionViewModel

    var body: some View {
        if let option = optionViewModel.selectedOption {
            OptionWorkspaceView(option: option)
                .id(option.id)
        } else {
            EmptyOptionView()
        }
    }
}

// MARK: - Workspace

private struct OptionWorkspaceView: View {
    let option: SpurOption
    @EnvironmentObject var optionViewModel: OptionViewModel
    @StateObject private var webViewStore = WebViewStore()
    @State private var showCreatePR = false

    private var isRunning: Bool { optionViewModel.isServerRunning(option.id) }
    /// Uses the URL detected from server log output; falls back to the allocated port.
    private var localURL: URL {
        optionViewModel.detectedServerURLs[option.id]
            ?? URL(string: "http://localhost:\(option.port)")
            ?? URL(string: "about:blank")!
    }

    var body: some View {
        VStack(spacing: 0) {
            // Browser chrome bar
            BrowserChromeBar(
                url: localURL.host.map { "\($0):\(localURL.port ?? option.port)" } ?? "localhost:\(option.port)",
                isRunning: isRunning,
                devCommand: Binding(
                    get: { option.devCommand },
                    set: { optionViewModel.updateDevCommand($0, for: option.id) }
                ),
                onReload: { webViewStore.reload() },
                onOpenBrowser: { NSWorkspace.shared.open(localURL) },
                onOpenTerminal: { optionViewModel.openInTerminal() },
                onCreatePR: { showCreatePR = true },
                onStartStop: {
                    if isRunning { optionViewModel.stopServer() }
                    else { optionViewModel.startServer() }
                }
            )

            Rectangle().fill(SpurColors.border).frame(height: 1)

            // Preview area
            if isRunning {
                WebPreviewView(url: localURL, store: webViewStore)
            } else {
                ServerOffPlaceholder(
                    onStart: { optionViewModel.startServer() }
                )
            }
        }
        .background(SpurColors.background)
        .sheet(isPresented: $showCreatePR) {
            CreatePRSheet(option: option)
        }
    }
}

// MARK: - Browser chrome

private struct BrowserChromeBar: View {
    let url: String
    let isRunning: Bool
    @Binding var devCommand: String
    let onReload: () -> Void
    let onOpenBrowser: () -> Void
    let onOpenTerminal: () -> Void
    let onCreatePR: () -> Void
    let onStartStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Traffic lights (decorative)
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "FF5F57")).frame(width: 11, height: 11)
                Circle().fill(Color(hex: "FEBC2E")).frame(width: 11, height: 11)
                Circle().fill(Color(hex: "28C840")).frame(width: 11, height: 11)
            }
            .padding(.leading, 4)

            Spacer()

            // URL pill
            HStack(spacing: 5) {
                Circle()
                    .fill(isRunning ? SpurColors.accent : SpurColors.textMuted)
                    .frame(width: 6, height: 6)
                Text(url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(SpurColors.textSecondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(SpurColors.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(SpurColors.border, lineWidth: 1))

            Spacer()

            // Actions
            HStack(spacing: 2) {
                iconButton("arrow.clockwise", help: "Reload", action: onReload, disabled: !isRunning)
                iconButton("safari", help: "Open in browser", action: onOpenBrowser, disabled: !isRunning)
                iconButton("terminal", help: "Open in Terminal.app", action: onOpenTerminal)
                iconButton("arrow.triangle.pull", help: "Create PR", action: onCreatePR)
            }

            Rectangle().fill(SpurColors.border).frame(width: 1, height: 16)

            // Dev command + start/stop
            TextField("dev command", text: $devCommand)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundColor(SpurColors.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(SpurColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(SpurColors.border, lineWidth: 1))
                .frame(width: 150)
                .disabled(isRunning)

            Button(isRunning ? "Stop" : "Start") { onStartStop() }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isRunning ? Color(hex: "F87171") : SpurColors.accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isRunning ? Color(hex: "F87171").opacity(0.1) : SpurColors.portBadgeBg)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .buttonStyle(.plain)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SpurColors.surface)
    }

    @ViewBuilder
    private func iconButton(
        _ name: String,
        help: String,
        action: @escaping () -> Void,
        disabled: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12))
                .foregroundColor(disabled ? SpurColors.textMuted : SpurColors.textSecondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}

// MARK: - Server off placeholder

private struct ServerOffPlaceholder: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.circle")
                .font(.system(size: 48))
                .foregroundColor(SpurColors.textMuted)
            Text("Dev server not running")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SpurColors.textSecondary)
            Button("Start Server", action: onStart)
                .buttonStyle(GreenButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpurColors.background)
    }
}

// MARK: - Empty option view

private struct EmptyOptionView: View {
    @EnvironmentObject var prototypeViewModel: PrototypeViewModel
    @State private var showNewOption = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(SpurColors.textMuted)
            Text("No worktree selected")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SpurColors.textSecondary)
            if let prototype = prototypeViewModel.selectedPrototype {
                Button("New Option") { showNewOption = true }
                    .buttonStyle(GreenButtonStyle())
                    .sheet(isPresented: $showNewOption) { NewOptionSheet(prototype: prototype) }
            } else {
                Text("Select a worktree from the sidebar")
                    .font(.system(size: 11))
                    .foregroundColor(SpurColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpurColors.background)
    }
}
