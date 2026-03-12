import Foundation

extension String {
    /// Wraps the string in single quotes and escapes any embedded single quotes,
    /// making it safe to embed in a shell `-c` argument.
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum Constants {
    static let appSubsystem = "com.spur.app"
    static let spurDirectoryName = ".spur"
    static let worktreeDirectoryName = "spur-worktrees"
    static let branchPrefix = "exp"
    static let defaultBaseBranch = "main"
    static let defaultDevCommand = "npm run dev"
    static let devServerPortRange: ClosedRange<Int> = 3001...3999
    static let devServerKillTimeout: TimeInterval = 5.0

    /// Package manager for the given repo directory, detected from lockfiles.
    static func packageManager(at repoPath: String) -> PackageManager {
        let fm = FileManager.default
        if fm.fileExists(atPath: (repoPath as NSString).appendingPathComponent("pnpm-lock.yaml")) { return .pnpm }
        if fm.fileExists(atPath: (repoPath as NSString).appendingPathComponent("yarn.lock"))      { return .yarn }
        return .npm
    }

    enum PackageManager {
        case pnpm, yarn, npm
        var installCommand: String {
            switch self {
            case .pnpm: return "pnpm install --prefer-offline --frozen-lockfile"
            case .yarn: return "yarn install --frozen-lockfile"
            case .npm:  return "npm ci"
            }
        }
    }
}
