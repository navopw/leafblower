import XCTest
@testable import Leafblower

@MainActor
final class DeleteServiceTests: XCTestCase {
    private func service() -> DeleteService {
        DeleteService(moveItemToTrash: { url in
            try FileManager.default.removeItem(at: url)
        })
    }

    private func identity(of url: URL) -> FileIdentity {
        FileSystemEntry.read(atPath: url.path)!.identity
    }

    private func homeTempDir() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".leafblower-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func buildDemoTree(root: URL) -> ScanJob {
        let subdir = root.appendingPathComponent("subdir")
        try! FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let fileA = subdir.appendingPathComponent("file_a.txt")
        let fileB = subdir.appendingPathComponent("file_b.txt")
        let topFile = root.appendingPathComponent("top_file.txt")

        try! "hello".write(to: fileA, atomically: true, encoding: .utf8)
        try! "hi there".write(to: fileB, atomically: true, encoding: .utf8)
        try! "hey".write(to: topFile, atomically: true, encoding: .utf8)

        let nodeFileA = Node(id: "file_a", name: "file_a.txt", path: fileA.path, parentID: "subdir", sizeBytes: 5, isDir: false, fileIdentity: identity(of: fileA))
        let nodeFileB = Node(id: "file_b", name: "file_b.txt", path: fileB.path, parentID: "subdir", sizeBytes: 8, isDir: false, fileIdentity: identity(of: fileB))
        let nodeSubdir = Node(id: "subdir", name: "subdir", path: subdir.path, parentID: "root", sizeBytes: 13, isDir: true, childCount: 2, hasChildren: true, children: [nodeFileA, nodeFileB], fileIdentity: identity(of: subdir))
        let nodeTopFile = Node(id: "top_file", name: "top_file.txt", path: topFile.path, parentID: "root", sizeBytes: 3, isDir: false, fileIdentity: identity(of: topFile))
        let nodeRoot = Node(id: "root", name: "root", path: root.path, sizeBytes: 16, isDir: true, childCount: 2, hasChildren: true, children: [nodeSubdir, nodeTopFile], fileIdentity: identity(of: root))

        return ScanJob(
            id: "test_scan",
            rootPath: root.path,
            status: .complete,
            rootNode: nodeRoot,
            nodeIndex: [
                "root": nodeRoot,
                "subdir": nodeSubdir,
                "file_a": nodeFileA,
                "file_b": nodeFileB,
                "top_file": nodeTopFile
            ]
        )
    }

    func testRejectsScanRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let job = ScanJob(
            id: "test",
            rootPath: root.path,
            status: .complete,
            nodeIndex: [
                "root": Node(id: "root", name: "test", path: root.path, sizeBytes: 0, isDir: true)
            ]
        )
        let svc = service()
        let resp = svc.execute(job: job, nodeIDs: ["root"])
        XCTAssertEqual(resp.failed.count, 1)
        XCTAssertEqual(resp.failed.first?.error, "cannot move scan root")
    }

    func testRejectsNonexistentNode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let job = ScanJob(
            id: "test",
            rootPath: root.path,
            status: .complete,
            nodeIndex: [:]
        )
        let svc = service()
        let resp = svc.execute(job: job, nodeIDs: ["fake_node"])
        XCTAssertEqual(resp.failed.count, 1)
        XCTAssertEqual(resp.failed.first?.error, "node not found in scan")
    }

    func testDeletesFileSuccessfully() async throws {
        let svc = service()
        let root = try homeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("test.txt")
        try "test".write(to: file, atomically: true, encoding: .utf8)

        let fileNode = Node(
            id: "file1",
            name: "test.txt",
            path: file.path,
            parentID: "root",
            sizeBytes: 0,
            isDir: false,
            fileIdentity: identity(of: file)
        )
        let rootNode = Node(
            id: "root",
            name: "root",
            path: root.path,
            sizeBytes: 0,
            isDir: true,
            childCount: 1,
            hasChildren: true,
            children: [fileNode],
            fileIdentity: identity(of: root)
        )
        let job = ScanJob(
            id: "test",
            rootPath: root.path,
            status: .complete,
            rootNode: rootNode,
            nodeIndex: [
                "root": rootNode,
                "file1": fileNode
            ]
        )

        let resp = svc.execute(job: job, nodeIDs: ["file1"])
        XCTAssertEqual(resp.deleted.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testNormalizesNestedSelections() throws {
        let svc = service()
        let parent = Node(id: "dir", name: "dir", path: "/Users/test/parent", sizeBytes: 0, isDir: true)
        let child = Node(id: "file", name: "file", path: "/Users/test/parent/child.txt", parentID: "dir", sizeBytes: 0, isDir: false)

        let result = svc.normalizeSelection([parent, child])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "dir")
    }

    func testRejectsPathOutsideHome() throws {
        let job = ScanJob(
            id: "test",
            rootPath: "/tmp",
            status: .complete,
            nodeIndex: [
                "root": Node(id: "root", name: "root", path: "/tmp", sizeBytes: 0, isDir: true),
                "file1": Node(id: "file1", name: "file1", path: "/tmp/somefile", sizeBytes: 0, isDir: false)
            ]
        )

        let svc = service()
        let resp = svc.execute(job: job, nodeIDs: ["file1"])
        XCTAssertEqual(resp.failed.count, 1)
        XCTAssertEqual(resp.failed.first?.error, "removal is restricted to the home directory in v1")
    }

    func testDeletesDirectoryRecursively() async throws {
        let svc = service()
        let root = try homeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let job = buildDemoTree(root: root)
        let subdir = root.appendingPathComponent("subdir")

        let resp = svc.execute(job: job, nodeIDs: ["subdir"])
        XCTAssertEqual(resp.deleted.count, 1)
        XCTAssertEqual(resp.failed.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: subdir.path))

        for id in ["subdir", "file_a", "file_b"] {
            XCTAssertNil(job.nodeIndex[id], "node \(id) should have been removed from index")
        }
        XCTAssertNotNil(job.nodeIndex["root"], "root node should still be in index")
    }

    func testDeletesMultipleFiles() async throws {
        let svc = service()
        let root = try homeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let job = buildDemoTree(root: root)
        let resp = svc.execute(job: job, nodeIDs: ["file_a", "top_file"])

        XCTAssertEqual(resp.deleted.count, 2)
        XCTAssertEqual(resp.failed.count, 0)

        let fileA = root.appendingPathComponent("subdir/file_a.txt")
        let topFile = root.appendingPathComponent("top_file.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: topFile.path))

        let fileB = root.appendingPathComponent("subdir/file_b.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileB.path))
    }

    func testParentChildBothSelectedOnlyDeletesParentOnce() async throws {
        let svc = service()
        let root = try homeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let job = buildDemoTree(root: root)
        let subdir = root.appendingPathComponent("subdir")

        let resp = svc.execute(job: job, nodeIDs: ["subdir", "file_a"])
        XCTAssertEqual(resp.deleted.count, 1)
        XCTAssertEqual(resp.failed.count, 0)
        XCTAssertEqual(resp.deleted.first?.nodeID, "subdir")
        XCTAssertFalse(FileManager.default.fileExists(atPath: subdir.path))
    }

    func testPruneNodePropagatesSizeToRoot() async throws {
        let svc = service()
        let root = try homeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let job = buildDemoTree(root: root)
        let resp = svc.execute(job: job, nodeIDs: ["file_a"])

        XCTAssertEqual(resp.deleted.count, 1)
        XCTAssertEqual(job.nodeIndex["root"]?.sizeBytes, 11)
        XCTAssertEqual(job.nodeIndex["subdir"]?.sizeBytes, 8)
    }

    func testPruneNodeRemovesChildFromParentSlice() async throws {
        let svc = service()
        let root = try homeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let job = buildDemoTree(root: root)
        let resp = svc.execute(job: job, nodeIDs: ["top_file"])

        XCTAssertEqual(resp.deleted.count, 1)
        XCTAssertEqual(job.nodeIndex["root"]?.childCount, 1)
        for child in job.nodeIndex["root"]?.children ?? [] {
            XCTAssertNotEqual(child.id, "top_file")
        }
    }

    func testRejectsIncompleteJob() async throws {
        let svc = service()
        let root = try homeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let job = buildDemoTree(root: root)
        job.status = .running

        let resp = svc.execute(job: job, nodeIDs: ["file_a", "file_b"])
        XCTAssertEqual(resp.failed.count, 2)
        for f in resp.failed {
            XCTAssertEqual(f.error, "scan is not complete")
        }
    }

    func testRejectsDirectoryThatWasNotFullyScanned() throws {
        let root = try homeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let job = buildDemoTree(root: root)
        job.nodeIndex["subdir"]?.isScanComplete = false

        let response = service().execute(job: job, nodeIDs: ["subdir"])

        XCTAssertEqual(response.failed.count, 1)
        XCTAssertTrue(response.failed[0].error?.contains("not fully scanned") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("subdir").path))
    }

    func testRejectsItemChangedAfterScan() throws {
        let root = try homeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let job = buildDemoTree(root: root)
        let file = root.appendingPathComponent("top_file.txt")
        try "changed after scanning".write(to: file, atomically: true, encoding: .utf8)

        let response = service().execute(job: job, nodeIDs: ["top_file"])

        XCTAssertEqual(response.failed.count, 1)
        XCTAssertTrue(response.failed[0].error?.contains("changed") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testRejectsMountedVolumeRoot() throws {
        let root = try homeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let mount = root.appendingPathComponent("mounted")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)

        let mountNode = Node(
            id: "mount",
            name: "mounted",
            path: mount.path,
            parentID: "root",
            sizeBytes: 0,
            isDir: true,
            isMountPoint: true,
            fileIdentity: identity(of: mount)
        )
        let rootNode = Node(
            id: "root",
            name: "root",
            path: root.path,
            sizeBytes: 0,
            isDir: true,
            childCount: 1,
            hasChildren: true,
            children: [mountNode],
            fileIdentity: identity(of: root)
        )
        let job = ScanJob(
            id: "mount-test",
            rootPath: root.path,
            status: .complete,
            rootNode: rootNode,
            nodeIndex: ["root": rootNode, "mount": mountNode]
        )

        let response = service().execute(job: job, nodeIDs: ["mount"])

        XCTAssertEqual(response.failed.first?.error, "mounted volume roots cannot be moved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mount.path))
    }

    func testRejectsCriticalSystemPaths() {
        let criticals: [String] = ["/bin/sh", "/etc/passwd", "/usr/bin/env", "/System/Library"]
        for path in criticals {
            let err = SafetyValidator.validate(path: path, scanRoot: "/", homeDir: nil)
            XCTAssertNotNil(err, "expected validatePath to reject \(path), but it was allowed")
        }
    }

    func testRejectsPathOutsideScanRoot() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let scanRoot = home + "/leafblower-scanroot-test"
        let otherDir = home + "/leafblower-other-test"

        let err = SafetyValidator.validate(path: otherDir, scanRoot: scanRoot, homeDir: home)
        XCTAssertNotNil(err, "expected rejection for path outside scan root")
    }
}
