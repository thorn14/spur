import XCTest
@testable import Spur

final class ModelTests: XCTestCase {
    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Repo

    func testRepoRoundtrip() throws {
        let repo = Repo(path: "/Users/test/app", baseBranch: "main", devCommand: "npm run dev")
        let data = try encoder.encode(repo)
        let decoded = try decoder.decode(Repo.self, from: data)

        XCTAssertEqual(decoded.id, repo.id)
        XCTAssertEqual(decoded.path, repo.path)
        XCTAssertEqual(decoded.baseBranch, repo.baseBranch)
        XCTAssertEqual(decoded.devCommand, repo.devCommand)
    }

    func testRepoDefaultValues() {
        let repo = Repo(path: "/test")
        XCTAssertEqual(repo.baseBranch, "main")
        XCTAssertEqual(repo.devCommand, "npm run dev")
    }

    // MARK: - Experiment

    func testExperimentRoundtrip() throws {
        let optionId1 = UUID()
        let optionId2 = UUID()
        let exp = Experiment(
            name: "Color Study",
            slug: "color-study",
            optionIds: [optionId1, optionId2]
        )
        let data = try encoder.encode(exp)
        let decoded = try decoder.decode(Experiment.self, from: data)

        XCTAssertEqual(decoded.id, exp.id)
        XCTAssertEqual(decoded.name, "Color Study")
        XCTAssertEqual(decoded.slug, "color-study")
        XCTAssertEqual(decoded.optionIds, [optionId1, optionId2])
    }

    func testExperimentDefaultsEmptyOptionIds() {
        let exp = Experiment(name: "Test", slug: "test")
        XCTAssertTrue(exp.optionIds.isEmpty)
    }

    // MARK: - SpurOption

    func testOptionRoundtrip() throws {
        var option = SpurOption(
            experimentId: UUID(),
            name: "Warm Palette",
            slug: "warm-palette",
            branchName: "exp/color-study/warm-palette",
            worktreePath: "/spur-worktrees/color-study--warm-palette",
            port: 3001
        )
        option.forkedFromCommit = "abc1234"
        option.prURL = "https://github.com/example/repo/pull/42"
        option.prNumber = 42

        let data = try encoder.encode(option)
        let decoded = try decoder.decode(SpurOption.self, from: data)

        XCTAssertEqual(decoded.id, option.id)
        XCTAssertEqual(decoded.port, 3001)
        XCTAssertEqual(decoded.status, .idle)
        XCTAssertEqual(decoded.forkedFromCommit, "abc1234")
        XCTAssertEqual(decoded.prNumber, 42)
        XCTAssertEqual(decoded.prURL, "https://github.com/example/repo/pull/42")
        XCTAssertTrue(decoded.turns.isEmpty)
    }

    func testOptionStatusRoundtrip() throws {
        for status in [OptionStatus.idle, .running, .detached, .error] {
            var option = SpurOption(
                experimentId: UUID(), name: "X", slug: "x",
                branchName: "exp/x/x", worktreePath: "/x", port: 3001
            )
            option.status = status
            let data = try encoder.encode(option)
            let decoded = try decoder.decode(SpurOption.self, from: data)
            XCTAssertEqual(decoded.status, status)
        }
    }

    // MARK: - Turn

    func testTurnRoundtrip() throws {
        var turn = Turn(number: 1, label: "Initial layout", startCommit: "abc1230")
        turn.endCommit = "abc1234"
        turn.commitRange = ["abc1231", "abc1232", "abc1233", "abc1234"]

        let data = try encoder.encode(turn)
        let decoded = try decoder.decode(Turn.self, from: data)

        XCTAssertEqual(decoded.id, turn.id)
        XCTAssertEqual(decoded.number, 1)
        XCTAssertEqual(decoded.label, "Initial layout")
        XCTAssertEqual(decoded.startCommit, "abc1230")
        XCTAssertEqual(decoded.endCommit, "abc1234")
        XCTAssertEqual(decoded.commitRange, ["abc1231", "abc1232", "abc1233", "abc1234"])
    }

    func testTurnDefaultNilEndCommit() {
        let turn = Turn(number: 1, label: "Test", startCommit: "abc")
        XCTAssertNil(turn.endCommit)
        XCTAssertTrue(turn.commitRange.isEmpty)
    }

    // MARK: - AppState

    func testAppStateRoundtrip() throws {
        let repo = Repo(path: "/Users/test/app")
        var state = AppState(repo: repo)
        state.experiments = [Experiment(name: "E1", slug: "e1")]

        var option = SpurOption(
            experimentId: state.experiments[0].id,
            name: "O1", slug: "o1",
            branchName: "exp/e1/o1", worktreePath: "/wt", port: 3002
        )
        option.turns = [Turn(number: 1, label: "T1", startCommit: "abc")]
        state.options = [option]

        let data = try encoder.encode(state)
        let decoded = try decoder.decode(AppState.self, from: data)

        XCTAssertEqual(decoded.repoId, state.repoId)
        XCTAssertEqual(decoded.repoPath, "/Users/test/app")
        XCTAssertEqual(decoded.schemaVersion, AppState.currentSchemaVersion)
        XCTAssertEqual(decoded.experiments.count, 1)
        XCTAssertEqual(decoded.options.count, 1)
        XCTAssertEqual(decoded.options[0].turns.count, 1)
    }
}
