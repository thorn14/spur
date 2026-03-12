import XCTest
@testable import Spur

final class PersistenceServiceTests: XCTestCase {
    private var tempDirectory: URL!
    private var service: PersistenceService!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpurTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        service = try PersistenceService(baseDirectory: tempDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Save & Load

    func testSaveAndLoad() throws {
        let repo = Repo(path: "/Users/test/myapp")
        var state = AppState(repo: repo)
        state.prototypes = [Prototype(name: "Color Study", slug: "color-study")]

        try service.save(state)
        let loaded = try service.load(repoId: repo.id)

        XCTAssertEqual(loaded.repoId, state.repoId)
        XCTAssertEqual(loaded.repoPath, "/Users/test/myapp")
        XCTAssertEqual(loaded.prototypes.count, 1)
        XCTAssertEqual(loaded.prototypes[0].name, "Color Study")
    }

    func testSaveOverwritesPreviousState() throws {
        let repo = Repo(path: "/test")
        var state = AppState(repo: repo)
        try service.save(state)

        state.prototypes.append(Prototype(name: "New Prototype", slug: "new"))
        try service.save(state)

        let loaded = try service.load(repoId: repo.id)
        XCTAssertEqual(loaded.prototypes.count, 1)
        XCTAssertEqual(loaded.prototypes[0].name, "New Prototype")
    }

    func testSavePreservesOptions() throws {
        let repo = Repo(path: "/test")
        var state = AppState(repo: repo)
        let exp = Prototype(name: "E", slug: "e")
        state.prototypes = [exp]

        var option = SpurOption(
            prototypeId: exp.id, name: "O", slug: "o",
            branchName: "exp/e/o", worktreePath: "/wt/e--o", port: 3001
        )
        option.turns = [Turn(number: 1, label: "T1", startCommit: "abc123")]
        state.options = [option]

        try service.save(state)
        let loaded = try service.load(repoId: repo.id)

        XCTAssertEqual(loaded.options.count, 1)
        XCTAssertEqual(loaded.options[0].turns.count, 1)
        XCTAssertEqual(loaded.options[0].port, 3001)
    }

    // MARK: - Error Cases

    func testFileNotFoundThrows() {
        XCTAssertThrowsError(try service.load(repoId: UUID())) { error in
            guard case PersistenceError.fileNotFound = error else {
                XCTFail("Expected PersistenceError.fileNotFound, got \(error)")
                return
            }
        }
    }

    func testCorruptFileThrowsAndCreatesBackup() throws {
        let repo = Repo(path: "/test")
        let url = service.stateFileURL(for: repo.id)
        try "{ this is not valid JSON ]".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try service.load(repoId: repo.id)) { error in
            guard case PersistenceError.decodingFailed = error else {
                XCTFail("Expected PersistenceError.decodingFailed, got \(error)")
                return
            }
        }

        // Backup should exist
        let backupURL = url.deletingPathExtension().appendingPathExtension("backup.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path),
                      "Backup file should be created alongside corrupt file")
    }

    // MARK: - List & Delete

    func testListRepoIds() throws {
        let repo1 = Repo(path: "/test/1")
        let repo2 = Repo(path: "/test/2")
        try service.save(AppState(repo: repo1))
        try service.save(AppState(repo: repo2))

        let ids = try service.listRepoIds()
        XCTAssertTrue(ids.contains(repo1.id))
        XCTAssertTrue(ids.contains(repo2.id))
    }

    func testListRepoIdsSortedByModificationDateDescending() throws {
        let repo1 = Repo(path: "/test/1")
        let repo2 = Repo(path: "/test/2")
        try service.save(AppState(repo: repo1))
        // Guarantee repo2 has a strictly later mtime by touching it after a short delay.
        Thread.sleep(forTimeInterval: 0.05)
        try service.save(AppState(repo: repo2))

        let ids = try service.listRepoIds()
        XCTAssertEqual(ids.first, repo2.id, "Most recently saved repo must be first")
        XCTAssertEqual(ids.last,  repo1.id)
    }

    func testListRepoIdsExcludesBackupFiles() throws {
        let repo = Repo(path: "/test")
        let url = service.stateFileURL(for: repo.id)
        let backupURL = url.deletingPathExtension().appendingPathExtension("backup.json")
        try "{}".write(to: backupURL, atomically: true, encoding: .utf8)

        let ids = try service.listRepoIds()
        XCTAssertTrue(ids.isEmpty, "Backup files must not appear in listRepoIds()")
    }

    func testDeleteRemovesFile() throws {
        let repo = Repo(path: "/test")
        try service.save(AppState(repo: repo))
        try service.delete(repoId: repo.id)

        XCTAssertThrowsError(try service.load(repoId: repo.id))
    }

    // MARK: - State File URL

    func testStateFileURL() {
        let id = UUID()
        let url = service.stateFileURL(for: id)
        XCTAssertEqual(url.lastPathComponent, "\(id.uuidString).json")
        XCTAssertEqual(url.deletingLastPathComponent(), tempDirectory)
    }
}
