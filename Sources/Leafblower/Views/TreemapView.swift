import SwiftUI

struct TreemapView: View {
    @State private var rendered: RenderedTreemap?

    var body: some View {
        GeometryReader { geometry in
            let job = ScanManager.shared.currentJob

            if let job, let root = job.rootNode {
                let zoomID = ScanManager.shared.currentZoomNodeID
                let zoomNode = job.nodeIndex[zoomID] ?? root
                let size = geometry.size
                // Bucket the size so small resize deltas don't trigger a re-render.
                let bw = (size.width / 4).rounded() * 4
                let bh = (size.height / 4).rounded() * 4
                let key = "\(job.id)|\(zoomID)|\(Int(bw))x\(Int(bh))|\(job.treeRevision)"
                let scale = NSScreen.main?.backingScaleFactor ?? 2

                ZStack(alignment: .bottomLeading) {
                    Color(.windowBackgroundColor)

                    if let rendered, rendered.image.size.width > 0 {
                        Image(nsImage: rendered.image)
                            .resizable()
                            .interpolation(.low)
                            .frame(width: size.width, height: size.height)

                        overlay(rendered: rendered, displaySize: size)
                    }

                    if rendered == nil || rendered?.key != key {
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    ClickCatcher { location, clickCount, shift in
                        handleClick(location, clickCount: clickCount, shift: shift,
                                    displaySize: size, job: job)
                    }
                }
                .task(id: key) {
                    let node = zoomNode
                    let renderSize = CGSize(width: max(bw, 4), height: max(bh, 4))
                    let result = await Task.detached(priority: .userInitiated) {
                        TreemapRenderer.render(node: node, size: renderSize, scale: scale, key: key)
                    }.value
                    if !Task.isCancelled {
                        rendered = result
                    }
                }
            } else if let job, job.status == .running || job.status == .queued {
                placeholder {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("Scanning…")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Building the tree — progress is shown below.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            } else if let job, job.status == .failed {
                placeholder {
                    Image(systemName: "xmark.octagon")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                    Text("Scan failed")
                        .font(.title3)
                    Text(job.warnings.first?.code ?? "Unknown error")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                placeholder {
                    Image(systemName: "wind")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Enter a path and click Scan to start")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Live overlay (labels + selection)

    /// Lightweight `Canvas` drawn on top of the cached bitmap. It only draws labels
    /// for large tiles and the current selection, so it can repaint freely without
    /// touching the (expensive) tile rendering.
    private func overlay(rendered: RenderedTreemap, displaySize: CGSize) -> some View {
        let selected = ScanManager.shared.selectedNodeIDs
        let sx = rendered.size.width > 0 ? displaySize.width / rendered.size.width : 1
        let sy = rendered.size.height > 0 ? displaySize.height / rendered.size.height : 1

        func scaled(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
        }

        return Canvas { context, _ in
            // Name + human-readable size for comfortably large tiles only
            // (precomputed → few of them).
            for tile in rendered.labelTiles {
                let r = scaled(tile.rect)
                let name = Text(tile.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                let size = Text(FileSizeFormatter.string(from: tile.sizeBytes))
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.white.opacity(0.75))
                context.draw(name, at: CGPoint(x: r.midX, y: r.midY - 6), anchor: .center)
                context.draw(size, at: CGPoint(x: r.midX, y: r.midY + 7), anchor: .center)
            }

            // Folder header: name on the left, size on the right.
            for folder in rendered.layout.folderRects {
                let h = scaled(folder.header)
                guard h.width > 44 else { continue }
                let name = Text(folder.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                context.draw(name, at: CGPoint(x: h.minX + 7, y: h.midY), anchor: .leading)

                if h.width > 110 {
                    let size = Text(FileSizeFormatter.string(from: folder.sizeBytes))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                    context.draw(size, at: CGPoint(x: h.maxX - 7, y: h.midY), anchor: .trailing)
                }
            }

            // Highlight only the selected nodes (look up their rects directly).
            for id in selected {
                guard let rect = rendered.rectByID[id] else { continue }
                let r = scaled(rect)
                let path = Path(roundedRect: r, cornerRadius: 4)
                context.fill(path, with: .color(Color.accentColor.opacity(0.35)))
                context.stroke(path, with: .color(.white), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Interaction

    /// Handles a click immediately (no single/double disambiguation delay):
    /// - plain click toggles the node's selection (accumulates, persists on drill),
    /// - Shift+click drills into the folder,
    /// - double-click drills too, undoing the first click's selection toggle so it
    ///   has no side effect.
    private func handleClick(_ location: CGPoint, clickCount: Int, shift: Bool,
                             displaySize: CGSize, job: ScanJob) {
        guard let p = layoutPoint(location, displaySize: displaySize),
              let node = hitNode(p, job: job) else { return }

        if clickCount >= 2 {
            if !shift { ScanManager.shared.toggleSelection(nodeID: node.id) } // undo first-click toggle
            drill(node: node, job: job)
        } else if shift {
            drill(node: node, job: job)
        } else {
            ScanManager.shared.toggleSelection(nodeID: node.id)
        }
    }

    /// Maps a point in the displayed view into the rendered layout's coordinate space.
    private func layoutPoint(_ point: CGPoint, displaySize: CGSize) -> CGPoint? {
        guard let rendered else { return nil }
        guard displaySize.width > 0, displaySize.height > 0 else { return nil }
        return CGPoint(
            x: point.x * rendered.size.width / displaySize.width,
            y: point.y * rendered.size.height / displaySize.height
        )
    }

    /// Drills into the folder under the tapped node, leaving the selection untouched.
    /// If the node is itself an expandable directory, drills into it; if it's a tile
    /// shown inside a subfolder group, drills into that subfolder. Top-level files
    /// are ignored.
    private func drill(node: Node, job: ScanJob) {
        let zoomID = ScanManager.shared.currentZoomNodeID
        if node.isDir, node.children?.isEmpty == false {
            ScanManager.shared.zoomInto(nodeID: node.id)
        } else if let parentID = node.parentID, parentID != zoomID {
            ScanManager.shared.zoomInto(nodeID: parentID)
        }
    }

    /// Resolves the node under a point: a tile if one is hit, otherwise the subfolder
    /// whose header strip was clicked (so folder groups are selectable too).
    private func hitNode(_ point: CGPoint, job: ScanJob) -> Node? {
        guard let rendered else { return nil }
        if let tile = rendered.layout.tiles.first(where: { $0.rect.contains(point) }) {
            return job.nodeIndex[tile.nodeID]
        }
        if let folder = rendered.layout.folderRects.last(where: { $0.rect.contains(point) }) {
            return job.nodeIndex[folder.id]
        }
        return nil
    }

    // MARK: - Placeholder

    @ViewBuilder
    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10) {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
