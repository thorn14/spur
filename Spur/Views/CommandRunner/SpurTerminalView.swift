import AppKit
import SwiftTerm
import SwiftUI

/// Full VT100/VT220 terminal emulator backed by SwiftTerm's LocalProcessTerminalView.
/// Handles PTY setup, process lifecycle, and all terminal rendering internally.
///
/// `onEnterPressed` fires just before each Enter keystroke is delivered to the shell,
/// allowing callers to capture a checkpoint of the worktree state prior to running a command.
struct SpurTerminalView: NSViewRepresentable {
    let worktreePath: String
    /// Called when the user presses Enter/Return while this terminal has keyboard focus.
    /// Fires synchronously on the main thread before the keystroke reaches the shell.
    var onEnterPressed: (() -> Void)? = nil

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let term = LocalProcessTerminalView(frame: .zero)
        // Match Spur's dark UI
        term.nativeBackgroundColor = NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        term.nativeForegroundColor = NSColor(white: 0.85, alpha: 1)
        context.coordinator.onEnterPressed = onEnterPressed
        context.coordinator.termView = term
        context.coordinator.installEventMonitor()
        context.coordinator.start(term: term, worktreePath: worktreePath)
        return term
    }

    func updateNSView(_ term: LocalProcessTerminalView, context: Context) {
        context.coordinator.onEnterPressed = onEnterPressed
        guard context.coordinator.currentWorktreePath != worktreePath else { return }
        context.coordinator.start(term: term, worktreePath: worktreePath)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: -

    final class Coordinator {
        var currentWorktreePath: String?
        var onEnterPressed: (() -> Void)?
        weak var termView: LocalProcessTerminalView?
        private var eventMonitor: Any?

        /// Installs a local key event monitor that fires `onEnterPressed` when Enter is
        /// pressed while this terminal view (or a descendant) holds keyboard focus.
        func installEventMonitor() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let term = self.termView,
                      let window = term.window,
                      let responder = window.firstResponder as? NSView,
                      (responder === term || responder.isDescendant(of: term)) else {
                    return event
                }
                // Return key (keyCode 36) or numpad Enter (keyCode 76)
                if event.keyCode == 36 || event.keyCode == 76 {
                    self.onEnterPressed?()
                }
                return event
            }
        }

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

        deinit {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
