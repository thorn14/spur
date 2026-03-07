import Foundation

// TODO: [Phase 2] Implement ProcessRunner — see agents.md Prompt 4.
// CRITICAL: Always use executableURL + arguments. NEVER construct shell strings.

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessOutput {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}

final class ProcessRunner {
    // TODO: [Phase 2] Implement

    func run(
        executable: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        // TODO
        return ProcessResult(stdout: "", stderr: "", exitCode: 0)
    }

    func stream(
        executable: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil
    ) -> AsyncStream<ProcessOutput> {
        // TODO
        return AsyncStream { continuation in continuation.finish() }
    }
}
