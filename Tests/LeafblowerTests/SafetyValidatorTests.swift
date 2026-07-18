import XCTest
@testable import Leafblower

final class SafetyValidatorTests: XCTestCase {
    func testRejectsPathOutsideScanRoot() {
        let err = SafetyValidator.validate(path: "/other", scanRoot: "/target", homeDir: "/Users/test")
        XCTAssertNotNil(err)
    }

    func testRejectsRelativePath() {
        let err = SafetyValidator.validate(
            path: "Downloads/file.txt",
            scanRoot: "/Users/test",
            homeDir: "/Users/test"
        )
        XCTAssertEqual(err, "path is not absolute")
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
        XCTAssertEqual(err, "cannot move scan root")
    }

    func testRejectsHomeDirectoryWhenScanRootIsBroader() {
        let err = SafetyValidator.validate(path: "/Users/test", scanRoot: "/", homeDir: "/Users/test")
        XCTAssertEqual(err, "cannot move home directory")
    }

    func testRejectsItemsAlreadyInTrash() {
        let err = SafetyValidator.validate(
            path: "/Users/test/.Trash/file.txt",
            scanRoot: "/Users/test",
            homeDir: "/Users/test"
        )
        XCTAssertEqual(err, "items already in Trash cannot be removed by Leafblower")
    }

    func testRejectsPathWhoseParentSymlinkEscapesRoot() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let container = home.appendingPathComponent(".leafblower-safety-\(UUID().uuidString)")
        let root = container.appendingPathComponent("root")
        let outside = container.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let link = root.appendingPathComponent("escaped")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let err = SafetyValidator.validate(
            path: link.appendingPathComponent("file.txt").path,
            scanRoot: root.path,
            homeDir: home.path
        )

        XCTAssertEqual(err, "path resolves outside scan root")
    }

    func testAllowsRemovingSymlinkWithoutFollowingDestination() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let container = home.appendingPathComponent(".leafblower-safety-\(UUID().uuidString)")
        let root = container.appendingPathComponent("root")
        let outside = container.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let err = SafetyValidator.validate(
            path: link.path,
            scanRoot: root.path,
            homeDir: home.path,
            pathIsSymbolicLink: true
        )

        XCTAssertNil(err)
    }
}
