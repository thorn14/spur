import XCTest
@testable import Spur

final class DevServerServiceTests: XCTestCase {

    private var sut: DevServerService!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        sut = DevServerService()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpurDevServerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        sut.stopAll()
        sut = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - isRunning

    func testIsRunningFalseBeforeStart() {
        XCTAssertFalse(sut.isRunning(optionId: UUID()))
    }

    func testIsRunningTrueAfterStart() async throws {
        let id = UUID()
        let stream = sut.start(
            optionId: id,
            worktreePath: tempDir.path,
            port: 3100,
            command: "sleep 60"
        )
        // Give the process a moment to launch
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(sut.isRunning(optionId: id))
        // Cleanup
        try await sut.stop(optionId: id)
        _ = stream // keep alive
    }

    func testIsRunningFalseAfterStop() async throws {
        let id = UUID()
        let stream = sut.start(
            optionId: id,
            worktreePath: tempDir.path,
            port: 3101,
            command: "sleep 60"
        )
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(sut.isRunning(optionId: id))
        try await sut.stop(optionId: id)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(sut.isRunning(optionId: id))
        _ = stream
    }

    // MARK: - start / streaming

    func testStartStreamsOutput() async throws {
        let id = UUID()
        // Write a tiny shell script that prints two lines and exits
        let script = tempDir.appendingPathComponent("hello.sh")
        try "#!/bin/sh\necho hello\necho world\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let stream = sut.start(
            optionId: id,
            worktreePath: tempDir.path,
            port: 3102,
            command: script.path
        )

        var lines: [String] = []
        for await line in stream {
            lines.append(line)
        }

        XCTAssertTrue(lines.contains("hello"), "Expected 'hello' in output: \(lines)")
        XCTAssertTrue(lines.contains("world"), "Expected 'world' in output: \(lines)")
    }

    func testStartStreamsExitLine() async throws {
        let id = UUID()
        let script = tempDir.appendingPathComponent("exit42.sh")
        try "#!/bin/sh\nexit 42\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let stream = sut.start(
            optionId: id,
            worktreePath: tempDir.path,
            port: 3103,
            command: script.path
        )

        var lines: [String] = []
        for await line in stream {
            lines.append(line)
        }

        XCTAssertTrue(
            lines.last?.contains("42") == true,
            "Expected exit code 42 in final line, got: \(lines)"
        )
    }

    func testStartAlreadyRunningReturnsErrorStream() async throws {
        let id = UUID()
        let stream1 = sut.start(
            optionId: id,
            worktreePath: tempDir.path,
            port: 3104,
            command: "sleep 60"
        )
        try await Task.sleep(nanoseconds: 300_000_000)

        let stream2 = sut.start(
            optionId: id,
            worktreePath: tempDir.path,
            port: 3104,
            command: "sleep 60"
        )

        var errorLines: [String] = []
        for await line in stream2 {
            errorLines.append(line)
        }

        XCTAssertTrue(
            errorLines.contains(where: { $0.contains("already running") }),
            "Expected already-running error, got: \(errorLines)"
        )

        try await sut.stop(optionId: id)
        _ = stream1
    }

    // MARK: - stop

    func testStopNotRunningThrows() async {
        do {
            try await sut.stop(optionId: UUID())
            XCTFail("Expected DevServerError.notRunning to be thrown")
        } catch let error as DevServerError {
            if case .notRunning = error { /* expected */ } else {
                XCTFail("Unexpected DevServerError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testStopTerminatesProcess() async throws {
        let id = UUID()
        let stream = sut.start(
            optionId: id,
            worktreePath: tempDir.path,
            port: 3105,
            command: "sleep 60"
        )
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(sut.isRunning(optionId: id))
        try await sut.stop(optionId: id)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(sut.isRunning(optionId: id))
        _ = stream
    }

    // MARK: - Multiple concurrent options

    func testMultipleOptionsConcurrently() async throws {
        let id1 = UUID(), id2 = UUID()
        let stream1 = sut.start(optionId: id1, worktreePath: tempDir.path, port: 3106, command: "sleep 60")
        let stream2 = sut.start(optionId: id2, worktreePath: tempDir.path, port: 3107, command: "sleep 60")
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(sut.isRunning(optionId: id1))
        XCTAssertTrue(sut.isRunning(optionId: id2))

        try await sut.stop(optionId: id1)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(sut.isRunning(optionId: id1))
        XCTAssertTrue(sut.isRunning(optionId: id2))

        try await sut.stop(optionId: id2)
        _ = stream1; _ = stream2
    }

    // MARK: - stopAll

    func testStopAllTerminatesEverything() async throws {
        let id1 = UUID(), id2 = UUID()
        let s1 = sut.start(optionId: id1, worktreePath: tempDir.path, port: 3108, command: "sleep 60")
        let s2 = sut.start(optionId: id2, worktreePath: tempDir.path, port: 3109, command: "sleep 60")
        try await Task.sleep(nanoseconds: 300_000_000)

        sut.stopAll()
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertFalse(sut.isRunning(optionId: id1))
        XCTAssertFalse(sut.isRunning(optionId: id2))
        _ = s1; _ = s2
    }

    // MARK: - Empty / invalid command

    func testEmptyCommandReturnsErrorStream() async throws {
        let id = UUID()
        let stream = sut.start(optionId: id, worktreePath: tempDir.path, port: 3110, command: "   ")
        var lines: [String] = []
        for await line in stream {
            lines.append(line)
        }
        XCTAssertTrue(
            lines.contains(where: { $0.contains("empty command") }),
            "Expected empty-command error, got: \(lines)"
        )
    }

    func testWorktreeCwdIsApplied() async throws {
        // The script prints $PWD; verify it matches the worktree path
        let id = UUID()
        let script = tempDir.appendingPathComponent("pwd.sh")
        try "#!/bin/sh\npwd\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let stream = sut.start(
            optionId: id,
            worktreePath: tempDir.path,
            port: 3111,
            command: script.path
        )

        var lines: [String] = []
        for await line in stream {
            lines.append(line)
        }

        // /private/... vs /var/... on macOS — resolve symlinks for comparison
        let resolved = (tempDir.path as NSString).resolvingSymlinksInPath
        XCTAssertTrue(
            lines.contains(where: { ($0 as NSString).resolvingSymlinksInPath == resolved }),
            "Expected pwd=\(resolved) in output: \(lines)"
        )
    }
}
