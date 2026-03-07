import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum PortAllocatorError: Error, LocalizedError {
    case noPortsAvailable

    var errorDescription: String? {
        "No available ports in the \(Constants.devServerPortRange) range."
    }
}

/// Finds available TCP ports in the 3001–3999 range by attempting a bind.
enum PortAllocator {

    /// Returns an available port, skipping any in `excluding`.
    static func allocate(excluding: Set<Int> = []) throws -> Int {
        for port in Constants.devServerPortRange where !excluding.contains(port) {
            if isPortAvailable(port) {
                return port
            }
        }
        throw PortAllocatorError.noPortsAvailable
    }

    /// Returns `true` if the given TCP port can be bound on localhost.
    static func isPortAvailable(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var reuseAddr: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)

        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
