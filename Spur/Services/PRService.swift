import AppKit
import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "PRService")

enum PRServiceError: Error, LocalizedError {
    case ghNotInstalled
    case ghNotAuthenticated
    case remoteNotFound
    case prCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:           return "GitHub CLI (gh) is not installed. Opening browser instead."
        case .ghNotAuthenticated:       return "GitHub CLI not authenticated. Run 'gh auth login'."
        case .remoteNotFound:           return "No remote 'origin' found for this repository."
        case .prCreationFailed(let r):  return "PR creation failed: \(r)"
        }
    }
}

final class PRService {
    private let runner: ProcessRunner
    private let env = URL(fileURLWithPath: "/usr/bin/env")

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    // MARK: - Public API

    /// Attempts to create a PR via `gh pr create`.
    /// If `gh` is not installed or fails, falls back to opening a browser compare URL.
    /// Returns the PR URL on success.
    func createPR(
        repoPath: String,
        branch: String,
        title: String,
        body: String
    ) async throws -> String {
        // 1. Try gh CLI
        if let url = try await createViaCLI(repoPath: repoPath, branch: branch,
                                             title: title, body: body) {
            return url
        }

        // 2. Fallback: construct browser compare URL from remote
        let browserURL = try await compareBrowserURL(repoPath: repoPath, branch: branch)
        NSWorkspace.shared.open(browserURL)
        return browserURL.absoluteString
    }

    // MARK: - Private: gh CLI

    private func createViaCLI(
        repoPath: String,
        branch: String,
        title: String,
        body: String
    ) async throws -> String? {
        // Check gh exists
        let whichResult = try await runner.run(
            executable: env,
            arguments: ["which", "gh"],
            workingDirectory: URL(fileURLWithPath: repoPath)
        )
        guard whichResult.exitCode == 0 else {
            logger.info("gh not found, falling back to browser")
            return nil
        }

        let result = try await runner.run(
            executable: env,
            arguments: [
                "gh", "pr", "create",
                "--title", title,
                "--body", body,
                "--head", branch
            ],
            workingDirectory: URL(fileURLWithPath: repoPath)
        )

        if result.exitCode != 0 {
            let stderr = result.stderr
            if stderr.contains("authentication") || stderr.contains("auth") {
                throw PRServiceError.ghNotAuthenticated
            }
            logger.error("gh pr create failed (exit \(result.exitCode)): \(stderr)")
            throw PRServiceError.prCreationFailed(stderr.isEmpty ? result.stdout : stderr)
        }

        // gh outputs the PR URL as the last non-empty line starting with https://
        let url = result.stdout
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("https://") }
            .last
        logger.info("PR created via gh: \(url ?? "(no URL parsed)")")
        return url ?? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private: browser fallback

    private func compareBrowserURL(repoPath: String, branch: String) async throws -> URL {
        let result = try await runner.run(
            executable: env,
            arguments: ["git", "remote", "get-url", "origin"],
            workingDirectory: URL(fileURLWithPath: repoPath)
        )
        guard result.exitCode == 0 else {
            throw PRServiceError.remoteNotFound
        }
        let remoteURL = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (owner, repo) = Self.parseGitHubOwnerRepo(from: remoteURL) else {
            throw PRServiceError.remoteNotFound
        }
        let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        let urlString = "https://github.com/\(owner)/\(repo)/compare/\(encodedBranch)?expand=1"
        guard let url = URL(string: urlString) else {
            throw PRServiceError.prCreationFailed("Could not construct compare URL")
        }
        logger.info("Opened browser compare URL: \(urlString)")
        return url
    }

    // MARK: - Remote URL parsing

    /// Parses GitHub owner and repo name from an HTTPS or SSH remote URL.
    /// Handles:
    ///   https://github.com/owner/repo.git
    ///   git@github.com:owner/repo.git
    static func parseGitHubOwnerRepo(from remoteURL: String) -> (String, String)? {
        let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // HTTPS: https://github.com/owner/repo[.git]
        if url.hasPrefix("https://github.com/") || url.hasPrefix("http://github.com/") {
            var path = url
                .replacingOccurrences(of: "https://github.com/", with: "")
                .replacingOccurrences(of: "http://github.com/", with: "")
            if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return nil }
            return (parts[0], parts[1])
        }

        // SSH: git@github.com:owner/repo[.git]
        if url.hasPrefix("git@github.com:") {
            var path = url.replacingOccurrences(of: "git@github.com:", with: "")
            if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return nil }
            return (parts[0], parts[1])
        }

        return nil
    }
}
