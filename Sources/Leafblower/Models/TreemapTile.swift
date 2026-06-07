import SwiftUI

struct TreemapTile: Identifiable {
    let id: String
    let nodeID: String
    let name: String
    let rect: CGRect
    let color: Color
    let isDir: Bool
    let sizeBytes: Int64
}
