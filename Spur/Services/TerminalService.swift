import AppKit
import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "TerminalService")

enum TerminalServiceError: Error, LocalizedError {
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let reason): return "Could not open Terminal: \(reason)"
        }
    }
}

final class TerminalService {
    /// Opens Terminal.app and navigates to `worktreePath` via AppleScript.
    func openInTerminal(worktreePath: String) throws {
        // Build the AppleScript. We use `quoted form of` so that paths with
        // spaces, parentheses, etc. are shell-escaped safely.
        let source = """
        tell application "Terminal"
            do script "cd " & quoted form of "\(worktreePath.replacingOccurrences(of: "\"", with: "\\\""))"
            activate
        end tell
        """

        var errorDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw TerminalServiceError.scriptFailed("Could not create NSAppleScript")
        }
        script.executeAndReturnError(&errorDict)

        if let err = errorDict {
            let reason = err[NSAppleScript.errorMessage as NSString] as? String
                ?? err.description
            logger.error("TerminalService AppleScript error: \(reason)")
            throw TerminalServiceError.scriptFailed(reason)
        }

        logger.info("Opened Terminal at '\(worktreePath)'")
    }
}
