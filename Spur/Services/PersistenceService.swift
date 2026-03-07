import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "PersistenceService")

enum PersistenceError: Error, LocalizedError {
    case directoryCreationFailed(Error)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let e): return "Failed to create app directory: \(e.localizedDescription)"
        case .encodingFailed(let e):          return "Failed to encode state: \(e.localizedDescription)"
        case .decodingFailed(let e):          return "Failed to decode state: \(e.localizedDescription)"
        case .fileNotFound(let path):         return "State file not found at \(path)"
        }
    }
}

final class PersistenceService {
    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter baseDirectory: Override for testing. Defaults to `~/.spur`.
    init(baseDirectory: URL? = nil) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.baseDirectory = baseDirectory ?? home.appendingPathComponent(Constants.spurDirectoryName)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try createDirectoryIfNeeded()
    }

    // MARK: - Public API

    func stateFileURL(for repoId: UUID) -> URL {
        baseDirectory.appendingPathComponent("\(repoId.uuidString).json")
    }

    func save(_ state: AppState) throws {
        let url = stateFileURL(for: state.repoId)
        do {
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
            logger.debug("Saved state for repo \(state.repoId.uuidString)")
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.encodingFailed(error)
        }
    }

    func load(repoId: UUID) throws -> AppState {
        let url = stateFileURL(for: repoId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PersistenceError.fileNotFound(url.path)
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(AppState.self, from: data)
        } catch {
            // Backup the corrupt file before throwing so data is not silently lost.
            let backupURL = url.deletingPathExtension().appendingPathExtension("backup.json")
            try? FileManager.default.copyItem(at: url, to: backupURL)
            logger.error("Corrupt state file at \(url.path); backed up to \(backupURL.path)")
            throw PersistenceError.decodingFailed(error)
        }
    }

    /// Returns all repo UUIDs for which a state file exists.
    func listRepoIds() throws -> [UUID] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: baseDirectory, includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains("backup") }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }

    func delete(repoId: UUID) throws {
        let url = stateFileURL(for: repoId)
        try FileManager.default.removeItem(at: url)
        logger.debug("Deleted state for repo \(repoId.uuidString)")
    }

    // MARK: - Private

    private func createDirectoryIfNeeded() throws {
        do {
            try FileManager.default.createDirectory(
                at: baseDirectory, withIntermediateDirectories: true
            )
        } catch {
            throw PersistenceError.directoryCreationFailed(error)
        }
    }
}
