import Foundation

enum Constants {
    static let appSubsystem = "com.spur.app"
    static let spurDirectoryName = ".spur"
    static let worktreeDirectoryName = "spur-worktrees"
    static let branchPrefix = "exp"
    static let defaultBaseBranch = "main"
    static let defaultDevCommand = "npm run dev"
    static let devServerPortRange: ClosedRange<Int> = 3001...3999
    static let devServerKillTimeout: TimeInterval = 5.0
}
