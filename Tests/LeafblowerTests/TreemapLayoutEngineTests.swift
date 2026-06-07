import XCTest
import SwiftUI
@testable import Leafblower

final class TreemapLayoutEngineTests: XCTestCase {
    func testLayoutFillsBounds() {
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
        let tiles = TreemapLayoutEngine().layout(node: root, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(tiles.count, 2)
        let totalArea = tiles.reduce(0) { $0 + $1.rect.width * $1.rect.height }
        XCTAssertEqual(totalArea, 100 * 100, accuracy: 0.01)
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
}
