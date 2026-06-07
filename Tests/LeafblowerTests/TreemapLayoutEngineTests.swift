import XCTest
import SwiftUI
@testable import Leafblower

final class TreemapLayoutEngineTests: XCTestCase {
    func testTilesStayWithinBoundsAndAreProportional() {
        let root = Node(
            id: "root",
            name: "root",
            path: "/",
            sizeBytes: 100,
            isDir: true,
            children: [
                Node(id: "a", name: "a", path: "/a", sizeBytes: 30, isDir: false),
                Node(id: "b", name: "b", path: "/b", sizeBytes: 70, isDir: false)
            ]
        )
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let tiles = TreemapLayoutEngine().layout(node: root, in: bounds)
        XCTAssertEqual(tiles.count, 2)

        // Padding keeps every tile strictly inside the bounds.
        for tile in tiles {
            XCTAssertTrue(bounds.contains(tile.rect), "Tile \(tile.nodeID) escapes bounds: \(tile.rect)")
        }

        // Areas stay roughly proportional to size (b ~ 70/30 of a), allowing for the
        // uniform gap inset.
        let area = Dictionary(tiles.map { ($0.nodeID, $0.rect.width * $0.rect.height) },
                              uniquingKeysWith: { a, _ in a })
        let ratio = area["b"]! / area["a"]!
        XCTAssertEqual(ratio, 70.0 / 30.0, accuracy: 0.25)
    }

    func testNoOverlap() {
        let root = Node(
            id: "root",
            name: "root",
            path: "/",
            sizeBytes: 100,
            isDir: true,
            children: [
                Node(id: "a", name: "a", path: "/a", sizeBytes: 10, isDir: false),
                Node(id: "b", name: "b", path: "/b", sizeBytes: 20, isDir: false),
                Node(id: "c", name: "c", path: "/c", sizeBytes: 30, isDir: false),
                Node(id: "d", name: "d", path: "/d", sizeBytes: 40, isDir: false)
            ]
        )
        let tiles = TreemapLayoutEngine().layout(node: root, in: CGRect(x: 0, y: 0, width: 200, height: 100))
        for i in 0..<tiles.count {
            for j in (i + 1)..<tiles.count {
                XCTAssertFalse(tiles[i].rect.intersects(tiles[j].rect), "Tiles \(tiles[i].nodeID) and \(tiles[j].nodeID) overlap")
            }
        }
    }

    func testExpandsSubfoldersOneLevelDeep() {
        // root -> dir "sub" -> { file f1, dir "deep" -> file deepf }. Two levels are
        // shown (children + grandchildren), matching the reference's depth: 2.
        let deepf = Node(id: "deepf", name: "deepf", path: "/sub/deep/deepf", parentID: "deep", sizeBytes: 10, isDir: false)
        let deep = Node(id: "deep", name: "deep", path: "/sub/deep", parentID: "sub", sizeBytes: 10, isDir: true, children: [deepf])
        let f1 = Node(id: "f1", name: "f1.txt", path: "/sub/f1.txt", parentID: "sub", sizeBytes: 90, isDir: false)
        let sub = Node(id: "sub", name: "sub", path: "/sub", parentID: "root", sizeBytes: 100, isDir: true, children: [f1, deep])
        let root = Node(id: "root", name: "root", path: "/", sizeBytes: 100, isDir: true, children: [sub])

        let layout = TreemapLayoutEngine().compute(node: root, in: CGRect(x: 0, y: 0, width: 100, height: 100))

        // "sub" is expanded one level: it's recorded as a folder group and its
        // children become tiles.
        XCTAssertEqual(layout.folderRects.map(\.id), ["sub"])
        XCTAssertEqual(Set(layout.tiles.map(\.nodeID)), ["f1", "deep"])
        // "deep" is one level too far down — drawn as a single tile, not expanded.
        XCTAssertFalse(layout.tiles.contains { $0.nodeID == "deepf" })
    }

    func testEverySiblingTileGetsADistinctColor() {
        let children = (0..<16).map {
            Node(id: "f\($0)", name: "f\($0)", path: "/f\($0)", sizeBytes: Int64(16 - $0), isDir: false)
        }
        let root = Node(id: "root", name: "root", path: "/", sizeBytes: 136, isDir: true, children: children)
        let tiles = TreemapLayoutEngine().layout(node: root, in: CGRect(x: 0, y: 0, width: 400, height: 400))

        XCTAssertEqual(tiles.count, 16)
        XCTAssertEqual(Set(tiles.map(\.color)).count, 16, "Sibling tiles should all have distinct colors")
    }

    func testEqualChildrenAreRoughlySquare() {
        // 16 equal files in a square bound: a squarified layout keeps each tile
        // close to square (a naive slice layout would make thin strips instead).
        let children = (0..<16).map {
            Node(id: "f\($0)", name: "f\($0)", path: "/f\($0)", sizeBytes: 10, isDir: false)
        }
        let root = Node(id: "root", name: "root", path: "/", sizeBytes: 160, isDir: true, children: children)
        let tiles = TreemapLayoutEngine().layout(node: root, in: CGRect(x: 0, y: 0, width: 400, height: 400))

        XCTAssertEqual(tiles.count, 16)
        for tile in tiles {
            let ratio = max(tile.rect.width, tile.rect.height) / min(tile.rect.width, tile.rect.height)
            XCTAssertLessThan(ratio, 2.0, "Tile \(tile.nodeID) is too elongated: \(ratio)")
        }
    }

    func testEmptyDirectoryDrawnAsSingleTile() {
        let emptyDir = Node(id: "e", name: "empty", path: "/empty", parentID: "root", sizeBytes: 0, isDir: true, children: [])
        let file = Node(id: "f", name: "f.txt", path: "/f.txt", parentID: "root", sizeBytes: 50, isDir: false)
        let root = Node(id: "root", name: "root", path: "/", sizeBytes: 50, isDir: true, children: [emptyDir, file])

        let tiles = TreemapLayoutEngine().layout(node: root, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        // Zero-sized empty dir is dropped; only the file remains.
        XCTAssertEqual(tiles.map(\.nodeID), ["f"])
    }
}
