import SwiftUI

/// Result of laying out a treemap: the tiles to draw plus the rectangle each
/// shown subfolder occupies (used to fill/outline/label folder groups and to make
/// the folder itself selectable via its header strip).
struct TreemapLayout {
    var tiles: [TreemapTile] = []
    var folderRects: [FolderRect] = []
}

struct FolderRect {
    let id: String
    let name: String
    let rect: CGRect
    /// The header strip at the top of `rect` — clickable target for selecting the
    /// folder itself.
    let header: CGRect
    let color: Color
    let sizeBytes: Int64
}

/// Squarified treemap layout, showing two levels — the same `depth: 2` the
/// reference leafblower's `/tree` endpoint serves.
///
/// Lays out the direct children of a node using the squarified tiling d3-hierarchy
/// uses by default (Bruls/Huizing/van Wijk). Each subfolder among those children is
/// then subdivided once more into *its* children, leaving a small header strip at
/// the top of the group (its clickable label). Anything below that level is drawn
/// as a single tile (drill into it to go further).
///
/// Colors are assigned hierarchically: the children split the color wheel into
/// equal hue arcs, and a subfolder's children take hues from within the parent's
/// arc. So every tile gets a distinct color, and a folder's contents share a hue
/// family close to the folder's own. Colors are kept darker so white labels read.
struct TreemapLayoutEngine {
    /// How many levels of subfolders to expand. 1 = current folder's children plus
    /// one level inside each (two levels total), matching the reference's depth: 2.
    var maxNesting = 1

    /// Subfolders whose rectangle is smaller than this (points, shortest side) are
    /// drawn as a single tile instead of being subdivided — too small to read.
    var minSubdivideSide: CGFloat = 40

    /// Height of the clickable header strip reserved at the top of each expanded
    /// subfolder.
    var headerHeight: CGFloat = 20

    /// Margin between the map and the view edges.
    var outerPadding: CGFloat = 6

    /// Gap left between adjacent tiles / groups.
    var tileGap: CGFloat = 2

    /// Inset between an expanded folder's edges and its children (below the header).
    var folderPadding: CGFloat = 3

    /// Tiles smaller than this (points, shortest side) are dropped — invisible at
    /// that size, and culling them keeps huge folders fast to lay out and draw.
    var minTileSide: CGFloat = 0.6

    /// Backwards-compatible entry point returning just the drawable tiles.
    func layout(node: Node, in bounds: CGRect) -> [TreemapTile] {
        compute(node: node, in: bounds).tiles
    }

    func compute(node: Node, in bounds: CGRect) -> TreemapLayout {
        var result = TreemapLayout()
        let area = bounds.insetBy(dx: outerPadding, dy: outerPadding)
        guard area.width > 0, area.height > 0, !Task.isCancelled else { return result }
        squarify(directChildren(of: node), rect: area, hue: 0 ... 1, depth: 0, into: &result)
        return result
    }

    private func directChildren(of node: Node) -> [Node] {
        (node.children ?? [])
            .filter { $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Squarified tiling

    /// Packs size-sorted children into the rectangle, growing each row only while
    /// doing so keeps the row's rectangles closer to square. `hue` is the slice of
    /// the color wheel these children divide between them.
    private func squarify(_ items: [Node], rect: CGRect, hue: ClosedRange<Double>,
                          depth: Int, into result: inout TreemapLayout) {
        let totalBytes = items.reduce(0.0) { $0 + Double($1.sizeBytes) }
        let rectArea = Double(rect.width) * Double(rect.height)
        guard totalBytes > 0, rectArea > 0 else { return }

        // One scale factor for the whole call: each strip we remove takes exactly
        // its share of area, so the remaining rect and remaining items stay in step.
        let areaPerByte = rectArea / totalBytes
        let hueStep = (hue.upperBound - hue.lowerBound) / Double(items.count)

        var remaining = rect
        var i = 0
        while i < items.count && !Task.isCancelled {
            let side = Double(min(remaining.width, remaining.height))
            if side <= 0 { break }

            // Grow the row while the worst (least square) aspect ratio improves.
            var rowSum = 0.0
            var rowMin = Double.greatestFiniteMagnitude
            var rowMax = 0.0
            var count = 0
            while i + count < items.count {
                let area = Double(items[i + count].sizeBytes) * areaPerByte
                let newSum = rowSum + area
                let newMin = Swift.min(rowMin, area)
                let newMax = Swift.max(rowMax, area)
                let current = worst(sum: rowSum, min: rowMin, max: rowMax, side: side)
                let candidate = worst(sum: newSum, min: newMin, max: newMax, side: side)
                if count == 0 || candidate <= current {
                    rowSum = newSum; rowMin = newMin; rowMax = newMax; count += 1
                } else {
                    break
                }
            }

            layoutRow(start: i, count: count, total: items.count, items: items,
                      rowSum: rowSum, areaPerByte: areaPerByte, remaining: &remaining,
                      side: side, hue: hue, hueStep: hueStep, depth: depth, into: &result)
            i += count
        }
    }

    /// Worst aspect ratio among a row's rectangles laid along a strip of length
    /// `side`. Lower is squarer; +∞ for an empty row so the first item always fits.
    private func worst(sum: Double, min: Double, max: Double, side: Double) -> Double {
        guard sum > 0 else { return .greatestFiniteMagnitude }
        let s2 = sum * sum
        let side2 = side * side
        return Swift.max(side2 * max / s2, s2 / (side2 * min))
    }

    /// Lays a finished row into a strip along the rectangle's shorter side and
    /// trims that strip off `remaining`.
    private func layoutRow(start: Int, count: Int, total: Int, items: [Node],
                           rowSum: Double, areaPerByte: Double, remaining: inout CGRect,
                           side: Double, hue: ClosedRange<Double>, hueStep: Double,
                           depth: Int, into result: inout TreemapLayout) {
        guard rowSum > 0 else { return }
        let strip = CGFloat(rowSum / side)
        let horizontal = remaining.width < remaining.height
        var cursor = horizontal ? remaining.minX : remaining.minY

        for k in 0 ..< count {
            if k.isMultiple(of: 256), Task.isCancelled { return }
            let idx = start + k
            let node = items[idx]
            let extent = CGFloat(Double(node.sizeBytes) * areaPerByte / Double(strip))
            let tileRect = horizontal
                ? CGRect(x: cursor, y: remaining.minY, width: extent, height: strip)
                : CGRect(x: remaining.minX, y: cursor, width: strip, height: extent)
            cursor += extent

            let arc = (hue.lowerBound + Double(idx) * hueStep) ... (hue.lowerBound + Double(idx + 1) * hueStep)
            place(node, rect: tileRect, arc: arc, index: idx, total: total, depth: depth, into: &result)
        }

        if horizontal {
            remaining = CGRect(x: remaining.minX, y: remaining.minY + strip,
                               width: remaining.width, height: remaining.height - strip)
        } else {
            remaining = CGRect(x: remaining.minX + strip, y: remaining.minY,
                               width: remaining.width - strip, height: remaining.height)
        }
    }

    /// Places a single node: subdivides it if it's an expandable subfolder we still
    /// have nesting budget for, otherwise draws it as one tile. Each node is inset by
    /// half the gap so neighbors end up separated by `tileGap`.
    private func place(_ node: Node, rect rawRect: CGRect, arc: ClosedRange<Double>,
                       index: Int, total: Int, depth: Int, into result: inout TreemapLayout) {
        let rect = rawRect.insetBy(dx: tileGap / 2, dy: tileGap / 2)
        guard rect.width >= minTileSide, rect.height >= minTileSide else { return }

        let tileColor = color(arc: arc, index: index, total: total, depth: depth)
        let children = directChildren(of: node)
        let canSubdivide = depth < maxNesting && node.isDir && !children.isEmpty
            && min(rect.width, rect.height) >= minSubdivideSide

        if canSubdivide {
            let header = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerHeight)
            result.folderRects.append(
                FolderRect(id: node.id, name: node.name, rect: rect, header: header,
                           color: tileColor, sizeBytes: node.sizeBytes)
            )
            let childRect = CGRect(x: rect.minX + folderPadding,
                                   y: rect.minY + headerHeight,
                                   width: rect.width - 2 * folderPadding,
                                   height: rect.height - headerHeight - folderPadding)
            squarify(children, rect: childRect, hue: arc, depth: depth + 1, into: &result)
        } else {
            result.tiles.append(
                TreemapTile(
                    id: node.id,
                    nodeID: node.id,
                    name: node.name,
                    rect: rect,
                    color: tileColor,
                    isDir: node.isDir,
                    sizeBytes: node.sizeBytes
                )
            )
        }
    }

    /// A distinct color from the node's hue arc. Hue is the arc's center (so a
    /// folder's contents share its hue family). Brightness is driven primarily by
    /// `depth`: each deeper level is brighter than its parent, so a folder is always
    /// darker than everything inside it. A small per-sibling step (kept well within
    /// the depth gap) keeps neighbors distinguishable. Built directly in sRGB so the
    /// renderer can resolve `.cgColor` cheaply.
    private func color(arc: ClosedRange<Double>, index: Int, total: Int, depth: Int) -> Color {
        let hue = (arc.lowerBound + arc.upperBound) / 2
        let fraction = total > 1 ? Double(index) / Double(total - 1) : 0
        let base = 0.48 + 0.22 * Double(depth)      // depth 0 ≈ dark, each level brighter
        let brightness = min(0.90, base + 0.08 * (1 - fraction))
        return Self.srgb(hue: hue, saturation: 0.66, brightness: brightness)
    }

    /// HSB → sRGB `Color`, so the resulting color carries a resolvable `.cgColor`.
    static func srgb(hue: Double, saturation: Double, brightness: Double) -> Color {
        let h = hue.truncatingRemainder(dividingBy: 1.0) * 6
        let sector = Int(h) % 6
        let f = h - Double(Int(h))
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch sector {
        case 0: (r, g, b) = (brightness, t, p)
        case 1: (r, g, b) = (q, brightness, p)
        case 2: (r, g, b) = (p, brightness, t)
        case 3: (r, g, b) = (p, q, brightness)
        case 4: (r, g, b) = (t, p, brightness)
        default: (r, g, b) = (brightness, p, q)
        }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
