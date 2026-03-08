import SwiftUI

/// Command input + streaming output panel for running arbitrary commands in an option's worktree.
struct CommandRunnerView: View {
    let worktreePath: String

    @StateObject private var viewModel = CommandRunnerViewModel()
    @State private var commandText = ""
    @FocusState private var inputFocused: Bool
    @EnvironmentObject var optionViewModel: OptionViewModel

    var body: some View {
        VStack(spacing: 0) {
            // ── Output area ──────────────────────────────────────────────
            LogOutputView(lines: viewModel.outputLines)
                .frame(maxHeight: .infinity)

            Divider()

            // ── Input bar ─────────────────────────────────────────────
            HStack(spacing: 6) {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                TextField("Enter command…", text: $commandText)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit { submit() }
                    .disabled(viewModel.isRunning)

                if viewModel.isRunning {
                    Button("Stop") { viewModel.cancel() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .font(.caption)
                } else {
                    Button {
                        submit()
                    } label: {
                        Image(systemName: "return")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .disabled(commandText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Run command (Return)")
                }

                Divider().frame(height: 16)

                Button {
                    viewModel.clearOutput()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Clear output")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear { inputFocused = true }
    }

    private func submit() {
        let cmd = commandText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty, !viewModel.isRunning else { return }
        commandText = ""
        viewModel.run(command: cmd, worktreePath: worktreePath)
    }
}
