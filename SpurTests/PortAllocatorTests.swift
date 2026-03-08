import XCTest
@testable import Spur

final class PortAllocatorTests: XCTestCase {

    func testAllocatesPortInRange() throws {
        let port = try PortAllocator.allocate()
        XCTAssertGreaterThanOrEqual(port, 3001)
        XCTAssertLessThanOrEqual(port, 3999)
    }

    func testExcludesSpecifiedPorts() throws {
        // Exclude a large block so we can verify exclusion works
        let excluded = Set(3001...3900)
        let port = try PortAllocator.allocate(excluding: excluded)
        XCTAssertFalse(excluded.contains(port))
        XCTAssertGreaterThanOrEqual(port, 3001)
        XCTAssertLessThanOrEqual(port, 3999)
    }

    func testPortAvailableReturnsBool() {
        // Just verify it returns a Bool without crashing; actual availability is environment-dependent.
        let result = PortAllocator.isPortAvailable(3001)
        XCTAssertTrue(result == true || result == false)
    }

    func testNoPortsAvailableThrows() {
        let allPorts = Set(Constants.devServerPortRange)
        XCTAssertThrowsError(try PortAllocator.allocate(excluding: allPorts)) { error in
            guard let portError = error as? PortAllocatorError,
                  case .noPortsAvailable = portError else {
                XCTFail("Expected PortAllocatorError.noPortsAvailable, got \(error)")
                return
            }
        }
    }

    func testNoPortsAvailableErrorDescription() {
        let error = PortAllocatorError.noPortsAvailable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testAllocatesDistinctPortsWhenCalledTwice() throws {
        // Allocate first port, then exclude it and allocate again
        let port1 = try PortAllocator.allocate()
        let port2 = try PortAllocator.allocate(excluding: [port1])
        XCTAssertNotEqual(port1, port2)
    }
}
