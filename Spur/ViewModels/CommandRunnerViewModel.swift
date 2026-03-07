import Combine
import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "CommandRunnerViewModel")

@MainActor
final class CommandRunnerViewModel: ObservableObject {
    @Published var outputLines: [String] = []
    @Published var isRunning = false
    @Published var error: Error?

    private let runner: ProcessRunner
    private let env = URL(fileURLWithPath: "/usr/bin/env")
    private var runningProcess: Task<Void, Never>?

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    // MARK: - Run

    /// Parses `command` into tokens and executes it in `worktreePath` via ProcessRunner.stream().
    func run(command: String, worktreePath: String) {
        let tokens = Self.tokenize(command)
        guard let executable = tokens.first, !executable.isEmpty else { return }

        isRunning = true
        error = nil
        outputLines.append("$ \(command)")

        let args = Array(tokens.dropFirst())
        let cwd = URL(fileURLWithPath: worktreePath)

        runningProcess = Task { [weak self] in
            guard let self else { return }
            let stream = self.runner.stream(
                executable: self.env,
                arguments: [executable] + args,
                workingDirectory: cwd
            )

            for await output in stream {
                guard !Task.isCancelled else { break }
                switch output {
                case .stdout(let line):
                    self.outputLines.append(line)
                case .stderr(let line):
                    self.outputLines.append(line)
                case .exit(let code):
                    if code != 0 {
                        self.outputLines.append("[exit \(code)]")
                    }
                }
            }
            self.isRunning = false
            self.runningProcess = nil
            logger.debug("Command finished: \(command)")
        }
    }

    /// Cancels the currently running command.
    func cancel() {
        runningProcess?.cancel()
        runningProcess = nil
        isRunning = false
    }

    func clearOutput() {
        outputLines = []
    }

    // MARK: - Command tokenizer

    /// Splits a shell-style command string into tokens, respecting single and double quotes.
    /// Examples:
    ///   "npm run build"               → ["npm", "run", "build"]
    ///   "git commit -m \"my message\"" → ["git", "commit", "-m", "my message"]
    static func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false

        for ch in command {
            switch ch {
            case "'":
                if inDouble { current.append(ch) } else { inSingle.toggle() }
            case "\"":
                if inSingle { current.append(ch) } else { inDouble.toggle() }
            case " ", "\t":
                if inSingle || inDouble {
                    current.append(ch)
                } else if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            default:
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
