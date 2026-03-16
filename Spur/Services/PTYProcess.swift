import Darwin
import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "PTYProcess")

/// Launches a subprocess attached to a pseudo-terminal so the child's shell
/// sources all init files and every tool (npm, pnpm, yarn, bun, cargo, …)
/// works identically to a real terminal — no environment hacks needed.
final class PTYProcess {

    enum PTYError: Error, LocalizedError {
        case openMasterFailed(Int32)
        case grantFailed(Int32)
        case unlockFailed(Int32)
        case ptsnameFailed
        case openSlaveFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .openMasterFailed(let e): return "posix_openpt failed errno=\(e)"
            case .grantFailed(let e):      return "grantpt failed errno=\(e)"
            case .unlockFailed(let e):     return "unlockpt failed errno=\(e)"
            case .ptsnameFailed:           return "ptsname returned nil"
            case .openSlaveFailed(let e):  return "open slave failed errno=\(e)"
            }
        }
    }

    private var masterFd: Int32 = -1
    private var slaveFd:  Int32 = -1
    private let process = Process()

    var isRunning: Bool { process.isRunning }
    var terminationStatus: Int32 { process.isRunning ? 0 : process.terminationStatus }

    init() throws {
        let (m, s) = try Self.makePTY()
        masterFd = m
        slaveFd  = s
        // Give the terminal a real window size so programs don't bail out or refuse to output.
        var ws = winsize()
        ws.ws_col = 220
        ws.ws_row = 50
        _ = ioctl(masterFd, TIOCSWINSZ, &ws)
    }

    deinit {
        if masterFd >= 0 { close(masterFd) }
        if slaveFd  >= 0 { close(slaveFd)  }
    }

    // MARK: - Launch

    func launch(shell: String, arguments: [String], environment: [String: String] = [:],
                workingDirectory: URL) throws {
        // Give the child its own copies of the slave fd for stdin/stdout/stderr.
        // Because slaveFd is a PTY, isatty() returns true in the child process,
        // which makes the shell source interactive init files (.zshrc etc.).
        let inH  = FileHandle(fileDescriptor: slaveFd, closeOnDealloc: false)
        let outH = FileHandle(fileDescriptor: slaveFd, closeOnDealloc: false)
        let errH = FileHandle(fileDescriptor: slaveFd, closeOnDealloc: false)

        // Merge caller overrides into the full parent environment so the shell
        // has HOME, PATH, USER, etc. and can source its init files.
        var env = ProcessInfo.processInfo.environment
        for (k, v) in environment { env[k] = v }

        process.executableURL       = URL(fileURLWithPath: shell)
        process.arguments           = arguments
        process.environment         = env
        process.currentDirectoryURL = workingDirectory
        process.standardInput       = inH
        process.standardOutput      = outH
        process.standardError       = errH

        try process.run()

        // Parent closes its slave copy — child has dup2'd copies.
        // This ensures EOF on master when the last slave handle closes.
        close(slaveFd)
        slaveFd = -1

        logger.info("PTY launched pid=\(self.process.processIdentifier) \(shell) \(arguments.joined(separator: " "))")
    }

    // MARK: - Output

    /// Returns an AsyncStream of stripped output lines.
    /// The stream finishes when the child process exits.
    func outputStream() -> AsyncStream<String> {
        let fd = masterFd
        return AsyncStream { [weak self] continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // `pending` holds a partial line that didn't end with \n yet.
                // `byteBuffer` carries over incomplete UTF-8 sequences that were
                // split across read() calls (e.g. multi-byte box-drawing chars).
                var pending = ""
                var byteBuffer = [UInt8]()
                var readBuf = [UInt8](repeating: 0, count: 4096)
                while true {
                    let n = read(fd, &readBuf, readBuf.count)
                    guard n > 0 else { break }
                    byteBuffer.append(contentsOf: readBuf[..<n])

                    // Try decoding as UTF-8, trimming up to 3 trailing bytes that
                    // may form an incomplete multi-byte sequence.
                    var raw = ""
                    var tailSize = 0
                    for trim in 0...3 {
                        let end = byteBuffer.count - trim
                        guard end > 0 else { break }
                        if let s = String(bytes: byteBuffer[..<end], encoding: .utf8) {
                            raw = s
                            tailSize = trim
                            break
                        }
                    }
                    byteBuffer = tailSize > 0 ? Array(byteBuffer[(byteBuffer.count - tailSize)...]) : []
                    let stripped = Self.stripANSI(raw)
                    // Split on \n. The last element is an incomplete line carried forward.
                    let parts = (pending + stripped).components(separatedBy: "\n")
                    for part in parts.dropLast() {
                        // Strip \r and control chars; skip blank lines
                        let t = part
                            .replacingOccurrences(of: "\r", with: "")
                            .trimmingCharacters(in: .controlCharacters)
                        if !t.isEmpty { continuation.yield(t) }
                    }
                    pending = parts.last ?? ""
                }
                // Flush any trailing partial line
                let t = pending
                    .replacingOccurrences(of: "\r", with: "")
                    .trimmingCharacters(in: .controlCharacters)
                if !t.isEmpty { continuation.yield(t) }
                let code = self?.terminationStatus ?? -1
                continuation.yield("[spur] Process exited with code \(code).")
                continuation.finish()
            }
        }
    }

    /// Yields raw terminal text chunks (preserving all ANSI escape sequences).
    /// Use this when feeding output to a proper ANSI renderer.
    func rawOutputStream() -> AsyncStream<String> {
        let fd = masterFd
        return AsyncStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var byteBuffer = [UInt8]()
                var readBuf = [UInt8](repeating: 0, count: 4096)
                while true {
                    let n = read(fd, &readBuf, readBuf.count)
                    guard n > 0 else { break }
                    byteBuffer.append(contentsOf: readBuf[..<n])
                    var text = ""
                    var tailSize = 0
                    for trim in 0...3 {
                        let end = byteBuffer.count - trim
                        guard end > 0 else { break }
                        if let s = String(bytes: byteBuffer[..<end], encoding: .utf8) {
                            text = s; tailSize = trim; break
                        }
                    }
                    byteBuffer = tailSize > 0 ? Array(byteBuffer[(byteBuffer.count - tailSize)...]) : []
                    if !text.isEmpty { continuation.yield(text) }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Input

    func write(_ text: String) {
        guard masterFd >= 0 else { return }
        var bytes = Array(text.utf8)
        _ = Darwin.write(masterFd, &bytes, bytes.count)
    }

    // MARK: - Control

    func terminateGracefully() async {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        setpgid(pid, pid)
        kill(-pid, SIGTERM)
        let proc = process
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let deadline = Date(timeIntervalSinceNow: Constants.devServerKillTimeout)
                while proc.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if proc.isRunning { kill(-pid, SIGKILL) }
                cont.resume()
            }
        }
    }

    func forceKill() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        kill(-pid, SIGKILL)
    }

    // MARK: - PTY creation

    private static func makePTY() throws -> (Int32, Int32) {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { throw PTYError.openMasterFailed(errno) }
        guard grantpt(master)  == 0 else { close(master); throw PTYError.grantFailed(errno) }
        guard unlockpt(master) == 0 else { close(master); throw PTYError.unlockFailed(errno) }
        guard let namePtr = ptsname(master) else { close(master); throw PTYError.ptsnameFailed }
        let slave = open(String(cString: namePtr), O_RDWR)
        guard slave >= 0 else { close(master); throw PTYError.openSlaveFailed(errno) }
        return (master, slave)
    }

    // MARK: - ANSI stripping

    /// Strips VT100/ANSI escape sequences so log output is plain text.
    static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            guard c == "\u{1B}" else { out.append(c); i = s.index(after: i); continue }
            let j = s.index(after: i)
            guard j < s.endIndex else { break }
            switch s[j] {
            case "[":   // CSI — ends at first byte in range 0x40–0x7E
                var k = s.index(after: j)
                while k < s.endIndex, let a = s[k].asciiValue, a < 0x40 { k = s.index(after: k) }
                i = k < s.endIndex ? s.index(after: k) : s.endIndex
            case "]":   // OSC — ends at BEL or ESC
                var k = s.index(after: j)
                while k < s.endIndex && s[k] != "\u{07}" && s[k] != "\u{1B}" { k = s.index(after: k) }
                i = k < s.endIndex ? s.index(after: k) : s.endIndex
            default:    // Two-byte sequence
                i = s.index(j, offsetBy: 1, limitedBy: s.endIndex) ?? s.endIndex
            }
        }
        return out
    }
}
