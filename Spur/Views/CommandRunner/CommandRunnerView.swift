import SwiftUI

/// Legacy command runner view — kept for compatibility. Main UI uses InlineTerminalView.
struct CommandRunnerView: View {
    let worktreePath: String

    @StateObject private var viewModel = CommandRunnerViewModel()
    @State private var commandText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(viewModel.outputLines.indices, id: \.self) { i in
                        Text(viewModel.outputLines[i])
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .id(i)
                    }
                    HStack(spacing: 0) {
                        Text("$ ").font(.system(size: 12, design: .monospaced)).foregroundColor(.accentColor)
                        TextField("", text: $commandText)
                            .font(.system(size: 12, design: .monospaced))
                            .textFieldStyle(.plain)
                            .focused($inputFocused)
                            .onSubmit { submit() }
                    }
                    .id("__prompt__")
                }
                .padding(10)
            }
            .onChange(of: viewModel.outputLines.count) { _ in proxy.scrollTo("__prompt__", anchor: .bottom) }
        }
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = true }
        .onAppear {
            viewModel.startIfNeeded(worktreePath: worktreePath)
            inputFocused = true
        }
    }

    private func submit() {
        let cmd = commandText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        commandText = ""
        viewModel.send(cmd)
        DispatchQueue.main.async { inputFocused = true }
    }
}
