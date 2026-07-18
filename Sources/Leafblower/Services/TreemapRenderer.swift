import SwiftUI
import AppKit

/// A fully-rendered treemap: the cached bitmap plus the layout it was drawn from
/// (kept for hit-testing and the live selection overlay). Rendering all tiles into
/// a single bitmap once — instead of redrawing thousands of tiles in a SwiftUI
/// `Canvas` every frame — is what keeps interaction smooth.
struct RenderedTreemap: @unchecked Sendable {
    let key: String
    let size: CGSize
    let image: NSImage
    let layout: TreemapLayout

    /// Rect of every selectable node (tiles and folder groups), so the live overlay
    /// can highlight the current selection without scanning all tiles each repaint.
    let rectByID: [String: CGRect]
    /// Tiles big enough to carry a name label — precomputed so the overlay only
    /// iterates the few labelled tiles, not every tile.
    let labelTiles: [TreemapTile]
}

enum TreemapRenderer {
    /// Corner radius for tiles / folder cards. Clamped to the rect so tiny tiles
    /// just stay square.
    private static let tileRadius: CGFloat = 3
    private static let folderRadius: CGFloat = 5

    /// Tiles at least this big (points) get a name label in the overlay.
    static let labelMinWidth: CGFloat = 80
    static let labelMinHeight: CGFloat = 28

    /// Computes the layout and renders it to a bitmap. Safe to call off the main
    /// thread (pure CoreGraphics, no AppKit view drawing).
    static func render(node: Node, size: CGSize, scale: CGFloat, key: String) -> RenderedTreemap? {
        guard !Task.isCancelled,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else { return nil }

        let layout = TreemapLayoutEngine().compute(
            node: node,
            in: CGRect(origin: .zero, size: size)
        )
        guard !Task.isCancelled,
              let image = drawImage(layout: layout, size: size, scale: scale) else { return nil }

        var rectByID: [String: CGRect] = [:]
        rectByID.reserveCapacity(layout.tiles.count + layout.folderRects.count)
        for tile in layout.tiles { rectByID[tile.nodeID] = tile.rect }
        for folder in layout.folderRects { rectByID[folder.id] = folder.rect }

        let labelTiles = layout.tiles.filter {
            $0.rect.width >= labelMinWidth && $0.rect.height >= labelMinHeight
        }

        return RenderedTreemap(key: key, size: size, image: image, layout: layout,
                               rectByID: rectByID, labelTiles: labelTiles)
    }

    private static func drawImage(layout: TreemapLayout, size: CGSize, scale: CGFloat) -> NSImage? {
        let requestedScale = min(4, max(1, scale))
        let pointArea = max(1, size.width * size.height)
        let maxPixelCount: CGFloat = 32_000_000
        let renderScale = min(requestedScale, sqrt(maxPixelCount / pointArea))
        let pxW = max(1, Int((size.width * renderScale).rounded()))
        let pxH = max(1, Int((size.height * renderScale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: pxW,
            height: pxH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Work in top-left origin point-space (flip the y axis), scaled for retina.
        ctx.translateBy(x: 0, y: CGFloat(pxH))
        ctx.scaleBy(x: renderScale, y: -renderScale)

        ctx.setShouldAntialias(true)

        let gray = CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        func cg(_ color: Color) -> CGColor { color.cgColor ?? gray }

        func fillRounded(_ rect: CGRect, _ color: CGColor, radius: CGFloat) {
            ctx.setFillColor(color)
            // Rounding is invisible on small tiles and the per-tile CGPath is the
            // expensive part on huge folders — only round when it shows.
            let side = min(rect.width, rect.height)
            if side < 6 {
                ctx.fill(rect)
            } else {
                let r = min(radius, side / 2)
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
                ctx.fillPath()
            }
        }

        // Folder backgrounds first, so each group's header strip and the gaps
        // between its children show the folder's color (a card behind the contents).
        for (index, folder) in layout.folderRects.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { return nil }
            fillRounded(folder.rect, cg(folder.color), radius: folderRadius)
        }

        for (index, tile) in layout.tiles.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { return nil }
            fillRounded(tile.rect, cg(tile.color), radius: tileRadius)
        }

        // A soft border around each folder card for definition.
        let folderStroke = CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
        ctx.setStrokeColor(folderStroke)
        ctx.setLineWidth(1)
        for (index, folder) in layout.folderRects.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { return nil }
            let inset = folder.rect.insetBy(dx: 0.5, dy: 0.5)
            let r = min(folderRadius, min(inset.width, inset.height) / 2)
            ctx.addPath(CGPath(roundedRect: inset, cornerWidth: r, cornerHeight: r, transform: nil))
            ctx.strokePath()
        }

        guard !Task.isCancelled, let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }
}
