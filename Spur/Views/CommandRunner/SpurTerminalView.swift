import AppKit
import SwiftTerm
import SwiftUI

/// Full VT100/VT220 terminal emulator backed by SwiftTerm's LocalProcessTerminalView.
/// Handles PTY setup, process lifecycle, and all terminal rendering internally.
struct SpurTerminalView: NSViewRepresentable {
    let worktreePath: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let term = LocalProcessTerminalView(frame: .zero)
        // Match Spur's dark UI
        term.nativeBackgroundColor = NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        term.nativeForegroundColor = NSColor(white: 0.85, alpha: 1)
        context.coordinator.start(term: term, worktreePath: worktreePath)
        return term
    }

    func updateNSView(_ term: LocalProcessTerminalView, context: Context) {
        guard context.coordinator.currentWorktreePath != worktreePath else { return }
        context.coordinator.start(term: term, worktreePath: worktreePath)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: -

    final class Coordinator {
        var currentWorktreePath: String?

        func start(term: LocalProcessTerminalView, worktreePath: String) {
            if term.process.running { term.terminate() }
            currentWorktreePath = worktreePath
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            term.startProcess(
                executable: shell,
                args: ["-l", "-i"],
                environment: nil,
                execName: nil,
                currentDirectory: worktreePath
            )
        }
    }
}
