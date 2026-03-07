import XCTest
@testable import Spur

final class SlugGeneratorTests: XCTestCase {

    func testBasicName() {
        XCTAssertEqual(SlugGenerator.generate(from: "Warm Palette"), "warm-palette")
    }

    func testLowercase() {
        XCTAssertEqual(SlugGenerator.generate(from: "LOUD SHOUTING"), "loud-shouting")
    }

    func testNumbers() {
        XCTAssertEqual(SlugGenerator.generate(from: "Option 2"), "option-2")
    }

    func testSpecialCharacters() {
        XCTAssertEqual(SlugGenerator.generate(from: "My Cool!@#$%^&*() Feature"), "my-cool-feature")
    }

    func testUnicode() {
        // Non-ASCII letters become hyphens
        let result = SlugGenerator.generate(from: "Café au lait")
        XCTAssertFalse(result.contains("é"))
        XCTAssertFalse(result.hasPrefix("-"))
        XCTAssertFalse(result.hasSuffix("-"))
    }

    func testConsecutiveSpaces() {
        XCTAssertEqual(SlugGenerator.generate(from: "hello   world"), "hello-world")
    }

    func testConsecutiveSpecialChars() {
        XCTAssertEqual(SlugGenerator.generate(from: "hello!!!world"), "hello-world")
    }

    func testEmptyString() {
        XCTAssertEqual(SlugGenerator.generate(from: ""), "option")
    }

    func testOnlySpecialChars() {
        XCTAssertEqual(SlugGenerator.generate(from: "!@#$%"), "option")
    }

    func testAlreadyValidSlug() {
        XCTAssertEqual(SlugGenerator.generate(from: "warm-palette"), "warm-palette")
    }

    func testLeadingSpecialChars() {
        let result = SlugGenerator.generate(from: "---hello")
        XCTAssertFalse(result.hasPrefix("-"))
    }

    func testTrailingSpecialChars() {
        let result = SlugGenerator.generate(from: "hello---")
        XCTAssertFalse(result.hasSuffix("-"))
    }

    func testLengthExactly50() {
        let name = String(repeating: "a", count: 50)
        let result = SlugGenerator.generate(from: name)
        XCTAssertEqual(result.count, 50)
    }

    func testLengthOver50() {
        let name = String(repeating: "a", count: 100)
        let result = SlugGenerator.generate(from: name)
        XCTAssertLessThanOrEqual(result.count, 50)
    }

    func testTruncationDoesNotLeaveTrailingHyphen() {
        // Create a 52-char name that will have a hyphen at position 50
        // "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab c" → truncated might end in "-"
        let name = String(repeating: "a", count: 49) + " " + String(repeating: "b", count: 10)
        let result = SlugGenerator.generate(from: name, maxLength: 50)
        XCTAssertLessThanOrEqual(result.count, 50)
        XCTAssertFalse(result.hasSuffix("-"))
    }

    func testCustomMaxLength() {
        let name = "hello world"
        let result = SlugGenerator.generate(from: name, maxLength: 5)
        XCTAssertLessThanOrEqual(result.count, 5)
    }

    func testUnderscoreBecomesHyphen() {
        XCTAssertEqual(SlugGenerator.generate(from: "hello_world"), "hello-world")
    }

    func testMixedContent() {
        let result = SlugGenerator.generate(from: "My App v2.0 (Beta)")
        XCTAssertEqual(result, "my-app-v2-0-beta")
    }
}
