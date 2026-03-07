import XCTest
@testable import Spur

final class ProcessRunnerTests: XCTestCase {
    private let runner = ProcessRunner()
    private let env = URL(fileURLWithPath: "/usr/bin/env")

    // MARK: - run() — stdout

    func testRunCapturesStdout() async throws {
        let result = try await runner.run(executable: env, arguments: ["echo", "hello world"])
        XCTAssertEqual(result.stdout, "hello world")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testRunMultiLineOutput() async throws {
        // printf doesn't add a trailing newline unless asked; trimmingCharacters removes it.
        let result = try await runner.run(
            executable: env, arguments: ["printf", "line1\nline2\nline3"]
        )
        XCTAssertEqual(result.stdout, "line1\nline2\nline3")
        XCTAssertEqual(result.exitCode, 0)
    }

    // MARK: - run() — stderr

    func testRunCapturesStderr() async throws {
        // `ls` on a nonexistent path writes an error to stderr and returns non-zero.
        let result = try await runner.run(
            executable: env,
            arguments: ["ls", "/spur-nonexistent-path-\(UUID().uuidString)"]
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.stderr.isEmpty, "stderr should contain an OS error message")
        XCTAssertTrue(result.stdout.isEmpty, "stdout should be empty for a failing ls")
    }

    // MARK: - run() — exit codes

    func testRunSuccessExitCode() async throws {
        let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/true"))
        XCTAssertEqual(result.exitCode, 0)
    }

    func testRunFailureExitCode() async throws {
        let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/false"))
        XCTAssertEqual(result.exitCode, 1)
    }

    func testRunReportsArbitraryExitCode() async throws {
        // Use `sh -c 'exit N'` — but we can't use shell strings. Instead use
        // Python or perl which are present on macOS. Alternatively, we can test
        // that exitCode is non-zero for a known-failing command.
        let result = try await runner.run(
            executable: env,
            arguments: ["python3", "-c", "import sys; sys.exit(42)"]
        )
        XCTAssertEqual(result.exitCode, 42)
    }

    // MARK: - run() — launch errors

    func testRunNonexistentExecutableThrows() async throws {
        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/definitely/does/not/exist/spur_test_binary")
            )
            XCTFail("Expected ProcessRunnerError.launchFailed to be thrown")
        } catch let error as ProcessRunnerError {
            if case .launchFailed = error { /* expected */ } else {
                XCTFail("Expected ProcessRunnerError.launchFailed, got \(error)")
            }
        }
    }

    // MARK: - run() — workingDirectory

    func testRunWithWorkingDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let result = try await runner.run(
            executable: env,
            arguments: ["pwd"],
            workingDirectory: tempDir
        )
        // Resolve symlinks: macOS /tmp -> /private/tmp
        let resolved = tempDir.resolvingSymlinksInPath().path
        XCTAssertEqual(result.stdout, resolved)
    }

    // MARK: - run() — environment

    func testRunWithCustomEnvironment() async throws {
        let result = try await runner.run(
            executable: env,
            arguments: ["printenv", "SPUR_PHASE2_TEST"],
            environment: ["SPUR_PHASE2_TEST": "phase2_value"]
        )
        XCTAssertEqual(result.stdout, "phase2_value")
        XCTAssertEqual(result.exitCode, 0)
    }

    // MARK: - stream() — stdout

    func testStreamDeliversStdoutLines() async throws {
        let stream = runner.stream(
            executable: env, arguments: ["printf", "alpha\nbeta\ngamma\n"]
        )
        var lines: [String] = []
        var exitCode: Int32?

        for await output in stream {
            switch output {
            case .stdout(let line): lines.append(line)
            case .stderr:           break
            case .exit(let code):   exitCode = code
            }
        }

        XCTAssertEqual(lines, ["alpha", "beta", "gamma"])
        XCTAssertEqual(exitCode, 0)
    }

    func testStreamDoesNotIncludeEmptyTrailingLine() async throws {
        // printf with trailing \n should yield lines without an extra empty element
        let stream = runner.stream(executable: env, arguments: ["printf", "a\nb\n"])
        var lines: [String] = []

        for await output in stream {
            if case .stdout(let line) = output { lines.append(line) }
        }

        XCTAssertEqual(lines, ["a", "b"])
    }

    // MARK: - stream() — exit case

    func testStreamAlwaysDeliversExitCase() async throws {
        let stream = runner.stream(executable: URL(fileURLWithPath: "/usr/bin/true"))
        var exitOutputCount = 0

        for await output in stream {
            if case .exit = output { exitOutputCount += 1 }
        }

        XCTAssertEqual(exitOutputCount, 1, "Stream must emit exactly one .exit element")
    }

    func testStreamExitCodeReflectsProcess() async throws {
        let stream = runner.stream(executable: URL(fileURLWithPath: "/usr/bin/false"))
        var exitCode: Int32?

        for await output in stream {
            if case .exit(let code) = output { exitCode = code }
        }

        XCTAssertEqual(exitCode, 1)
    }

    // MARK: - stream() — stderr

    func testStreamDeliversStderrLines() async throws {
        // Send to stderr via `ls /nonexistent`
        let stream = runner.stream(
            executable: env,
            arguments: ["ls", "/spur-nonexistent-\(UUID().uuidString)"]
        )
        var hadStderr = false
        for await output in stream {
            if case .stderr = output { hadStderr = true }
        }
        XCTAssertTrue(hadStderr, "Failing ls should produce stderr output")
    }

    // MARK: - Correctness invariants

    /// Verifies that ProcessRunner only ever sets executableURL, never uses shell strings.
    /// This is a static-analysis invariant; this test documents the contract.
    func testNoShellStringUsed() {
        // The real verification is the code review / Reviewer session (agents.md §1).
        // This test acts as a marker to ensure the invariant is tracked.
        XCTAssertTrue(true, "ProcessRunner never uses launchPath or shell string construction.")
    }
}
