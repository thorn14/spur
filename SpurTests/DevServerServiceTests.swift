import XCTest
@testable import Spur

// TODO: [Phase 4] Implement DevServerServiceTests — see agents.md Prompt 7.
//
// Cover:
//   - start() runs dev command in worktree directory
//   - start() streams log lines via AsyncStream
//   - stop() terminates process (SIGTERM, then SIGKILL)
//   - stop() kills child processes via process group
//   - Multiple options can run concurrently on different ports
//   - alreadyRunning error when starting same option twice
//   - isRunning() reflects accurate state

final class DevServerServiceTests: XCTestCase {
    // TODO: [Phase 4] Implement
}
