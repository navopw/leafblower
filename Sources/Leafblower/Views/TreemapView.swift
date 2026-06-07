import SwiftUI

struct TreemapView: View {
    var body: some View {
        GeometryReader { geometry in
            let job = ScanManager.shared.currentJob

            if let job, let root = job.rootNode {
                let zoomNode = job.nodeIndex[ScanManager.shared.currentZoomNodeID] ?? root
                let tiles = TreemapLayoutEngine().layout(
                    node: zoomNode,
                    in: geometry.frame(in: .local)
                )

                Canvas { context, size in
                    for tile in tiles {
                        let path = Path(tile.rect)
                        if ScanManager.shared.selectedNodeIDs.contains(tile.nodeID) {
                            context.fill(path, with: .color(Color.accentColor.opacity(0.7)))
                        } else {
                            context.fill(path, with: .color(tile.color))
                        }
                        context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 0.5)

                        if tile.rect.width > 40 && tile.rect.height > 20 {
                            let text = Text(tile.name)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                            context.draw(text, at: CGPoint(x: tile.rect.midX, y: tile.rect.midY))
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            handleTap(at: value.location, in: tiles, job: job)
                        }
                )
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

    @ViewBuilder
    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10) {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleTap(at location: CGPoint, in tiles: [TreemapTile], job: ScanJob) {
        guard let tile = tiles.first(where: { $0.rect.contains(location) }) else { return }
        let isShift = NSEvent.modifierFlags.contains(.shift)

        if isShift, let node = job.nodeIndex[tile.nodeID], node.isDir {
            ScanManager.shared.zoomInto(nodeID: tile.nodeID)
        } else {
            ScanManager.shared.toggleSelection(nodeID: tile.nodeID)
        }
    }
}
