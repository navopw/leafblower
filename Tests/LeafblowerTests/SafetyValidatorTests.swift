import XCTest
@testable import Leafblower

final class SafetyValidatorTests: XCTestCase {
    func testRejectsPathOutsideScanRoot() {
        let err = SafetyValidator.validate(path: "/other", scanRoot: "/target", homeDir: "/Users/test")
        XCTAssertNotNil(err)
    }

    func testRejectsCriticalPaths() {
        for path in ["/bin/sh", "/System/Library"] {
            let err = SafetyValidator.validate(path: path, scanRoot: "/", homeDir: nil)
            XCTAssertNotNil(err, "Should reject \(path)")
        }
    }

    func testAllowsValidPath() {
        let err = SafetyValidator.validate(path: "/Users/test/Downloads", scanRoot: "/Users/test", homeDir: "/Users/test")
        XCTAssertNil(err)
    }

    func testRejectsScanRoot() {
        let err = SafetyValidator.validate(path: "/Users/test", scanRoot: "/Users/test", homeDir: "/Users/test")
        XCTAssertEqual(err, "cannot delete scan root")
    }
}
