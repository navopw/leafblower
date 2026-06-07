import SwiftUI

struct TreemapLayoutEngine {
    private struct Item {
        let node: Node
        let value: Double
    }

    func layout(node: Node, in bounds: CGRect, depth: Int = 1) -> [TreemapTile] {
        guard depth > 0, let children = node.children, !children.isEmpty else { return [] }

        let totalValue = children.reduce(0) { $0 + Double($1.sizeBytes) }
        guard totalValue > 0 else { return [] }

        let items = children
            .map { Item(node: $0, value: max(Double($0.sizeBytes), 0)) }
            .sorted { $0.value > $1.value }

        var tiles: [TreemapTile] = []
        layoutItems(items, bounds: bounds, totalValue: totalValue, depth: depth, tiles: &tiles)
        return tiles
    }

    private func layoutItems(_ items: [Item], bounds: CGRect, totalValue: Double, depth: Int, tiles: inout [TreemapTile]) {
        guard !items.isEmpty else { return }

        var remaining = bounds
        var queue = items

        while !queue.isEmpty {
            var row: [Item] = []
            row.append(queue.removeFirst())

            while !queue.isEmpty {
                let worstCurrent = worstRatio(row: row, side: shorterSide(of: remaining))
                let worstWithNext = worstRatio(row: row + [queue[0]], side: shorterSide(of: remaining))
                if worstWithNext <= worstCurrent {
                    row.append(queue.removeFirst())
                } else {
                    break
                }
            }

            let rowValue = row.reduce(0) { $0 + $1.value }
            let (rowRects, newBounds) = layoutRow(row: row, value: rowValue, totalValue: totalValue, bounds: remaining)

            for (i, item) in row.enumerated() {
                let tile = TreemapTile(
                    id: item.node.id,
                    nodeID: item.node.id,
                    name: item.node.name,
                    rect: rowRects[i],
                    color: colorForNode(item.node)
                )
                tiles.append(tile)

                if depth > 1, let childChildren = item.node.children, !childChildren.isEmpty {
                    let childItems = childChildren
                        .map { Item(node: $0, value: max(Double($0.sizeBytes), 0)) }
                        .sorted { $0.value > $1.value }
                    let childTotal = childItems.reduce(0) { $0 + $1.value }
                    if childTotal > 0 {
                        layoutItems(childItems, bounds: rowRects[i], totalValue: childTotal, depth: depth - 1, tiles: &tiles)
                    }
                }
            }

            remaining = newBounds
        }
    }

    private func layoutRow(row: [Item], value: Double, totalValue: Double, bounds: CGRect) -> ([CGRect], CGRect) {
        let parentArea = bounds.width * bounds.height
        let rowProportion = value / totalValue
        let rowArea = parentArea * rowProportion

        var rects: [CGRect] = []

        if bounds.width >= bounds.height {
            // Horizontal strip along top
            let rowHeight = rowArea / bounds.width
            var x = bounds.minX
            for item in row {
                let width = bounds.width * (item.value / value)
                rects.append(CGRect(x: x, y: bounds.minY, width: width, height: rowHeight))
                x += width
            }
            let newBounds = CGRect(x: bounds.minX, y: bounds.minY + rowHeight, width: bounds.width, height: bounds.height - rowHeight)
            return (rects, newBounds)
        } else {
            // Vertical strip along left
            let rowWidth = rowArea / bounds.height
            var y = bounds.minY
            for item in row {
                let height = bounds.height * (item.value / value)
                rects.append(CGRect(x: bounds.minX, y: y, width: rowWidth, height: height))
                y += height
            }
            let newBounds = CGRect(x: bounds.minX + rowWidth, y: bounds.minY, width: bounds.width - rowWidth, height: bounds.height)
            return (rects, newBounds)
        }
    }

    private func shorterSide(of rect: CGRect) -> Double {
        min(rect.width, rect.height)
    }

    private func worstRatio(row: [Item], side: Double) -> Double {
        guard side > 0 else { return .infinity }
        let total = row.reduce(0) { $0 + $1.value }
        guard total > 0 else { return .infinity }
        let minValue = row.map(\.value).min()!
        let maxValue = row.map(\.value).max()!
        let sideSquared = side * side
        let totalSquared = total * total
        return max(
            (sideSquared * maxValue) / totalSquared,
            totalSquared / (sideSquared * minValue)
        )
    }

    private func colorForNode(_ node: Node) -> Color {
        var hash = 0
        for char in node.name.unicodeScalars {
            hash = Int(char.value) &+ ((hash << 5) &- hash)
        }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.65, brightness: 0.85)
    }
}
