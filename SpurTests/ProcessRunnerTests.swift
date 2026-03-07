import XCTest
@testable import Spur

// TODO: [Phase 2] Implement ProcessRunnerTests — see agents.md Prompt 5.
//
// Cover:
//   - run() with simple command (e.g., /usr/bin/true, /bin/echo)
//   - run() captures stdout and stderr separately
//   - run() reports correct exit codes (success + failure)
//   - run() throws for nonexistent executable
//   - stream() delivers stdout/stderr lines as ProcessOutput cases
//   - stream() delivers .exit case on completion
//   - No shell strings used anywhere (verified via code review in Reviewer session)

final class ProcessRunnerTests: XCTestCase {
    // TODO: [Phase 2] Implement
}
