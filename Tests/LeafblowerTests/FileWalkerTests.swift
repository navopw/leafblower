import XCTest
@testable import Leafblower

final class FileWalkerTests: XCTestCase {
    func testWalkSimpleDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let file1 = tempDir.appendingPathComponent("file1.txt")
        let file2 = tempDir.appendingPathComponent("file2.txt")
        try "hello".write(to: file1, atomically: true, encoding: .utf8)
        try "world".write(to: file2, atomically: true, encoding: .utf8)

        let walker = FileWalker(includeHidden: false, onProgress: { _ in })
        let (root, index, warnings) = try await walker.walk(scanID: "test", rootPath: tempDir.path)

        XCTAssertEqual(root.name, tempDir.lastPathComponent)
        XCTAssertEqual(root.children?.count, 2)
        XCTAssertEqual(index.count, 3)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testWalkNestedDirectories() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sub = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sub.appendingPathComponent("deep"), withIntermediateDirectories: true)

        let walker = FileWalker(includeHidden: false, onProgress: { _ in })
        let (root, index, warnings) = try await walker.walk(scanID: "test2", rootPath: tempDir.path)

        XCTAssertTrue(root.hasChildren)
        XCTAssertGreaterThanOrEqual(index.count, 3)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testIncludesSymlinksWithoutFollowingThem() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let file = tempDir.appendingPathComponent("file.txt")
        try "data".write(to: file, atomically: true, encoding: .utf8)

        let link = tempDir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        let walker = FileWalker(includeHidden: false, onProgress: { _ in })
        let (root, _, _) = try await walker.walk(scanID: "test3", rootPath: tempDir.path)

        XCTAssertEqual(root.children?.count, 2)
        let linkNode = root.children?.first { $0.name == "link" }
        XCTAssertEqual(linkNode?.isSymbolicLink, true)
        XCTAssertEqual(linkNode?.isDir, false)
    }

    func testMarksDirectoryIncompleteWhenHiddenItemsAreExcluded() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "hidden".write(
            to: tempDir.appendingPathComponent(".hidden"),
            atomically: true,
            encoding: .utf8
        )

        let walker = FileWalker(includeHidden: false, onProgress: { _ in })
        let (root, _, _) = try await walker.walk(scanID: "hidden", rootPath: tempDir.path)

        XCTAssertFalse(root.isScanComplete)
        XCTAssertTrue(root.children?.isEmpty == true)
    }
}
