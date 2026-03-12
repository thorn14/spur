import AppKit
import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "CommandRunnerViewModel")

@MainActor
final class CommandRunnerViewModel: ObservableObject {
    @Published var attributedOutput: NSAttributedString = NSAttributedString()
    // Keep outputLines for backward compat (ServerLogsView etc still use plain lines)
    @Published var outputLines: [String] = []

    private let ansiBuffer = ANSITerminalBuffer()
    private var pty: PTYProcess?
    private var readTask: Task<Void, Never>?
    private(set) var currentWorktreePath: String?

    // MARK: - Lifecycle

    func startIfNeeded(worktreePath: String) {
        if pty != nil && currentWorktreePath == worktreePath { return }
        stop()
        currentWorktreePath = worktreePath
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        do {
            let p = try PTYProcess()
            try p.launch(
                shell: shell,
                arguments: ["-l", "-i"],
                workingDirectory: URL(fileURLWithPath: worktreePath)
            )
            pty = p
            readTask = Task { [weak self] in
                guard let self else { return }
                for await chunk in p.rawOutputStream() {
                    let cleared = self.ansiBuffer.append(chunk)
                    if cleared { self.ansiBuffer.clear() }
                    self.attributedOutput = self.ansiBuffer.attributedText.copy() as! NSAttributedString
                }
                self.ansiBuffer.append("\n[spur] Shell exited.\n")
                self.attributedOutput = self.ansiBuffer.attributedText.copy() as! NSAttributedString
                self.pty = nil
                logger.info("Shell exited for \(worktreePath)")
            }
        } catch {
            ansiBuffer.append("[spur] Failed to start shell: \(error.localizedDescription)\n")
            attributedOutput = ansiBuffer.attributedText.copy() as! NSAttributedString
            logger.error("Shell start failed: \(error)")
        }
    }

    /// Writes a line of text to the shell's stdin, exactly as if the user typed it and pressed Enter.
    func send(_ text: String) {
        pty?.write(text + "\n")
    }

    func clearOutput() {
        ansiBuffer.clear()
        attributedOutput = NSAttributedString()
        outputLines = []
    }

    func stop() {
        pty?.forceKill()
        pty = nil
        readTask?.cancel()
        readTask = nil
    }
}
