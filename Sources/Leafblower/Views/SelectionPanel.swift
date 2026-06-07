import SwiftUI

struct SelectionPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Selection")
                    .font(.headline)
                Spacer()
                if selectionCount > 0 {
                    Text("\(selectionCount)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            if let job = ScanManager.shared.currentJob {
                let selected = ScanManager.shared.selectedNodeIDs
                    .compactMap { job.nodeIndex[$0] }
                    .sorted { $0.sizeBytes > $1.sizeBytes }

                if selected.isEmpty {
                    emptyState
                } else {
                    list(selected, root: job.rootPath)
                    Divider()
                    footer(selected)
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 250)
        .background(Color(.windowBackgroundColor))
    }

    private var selectionCount: Int { ScanManager.shared.selectedNodeIDs.count }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "hand.tap")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Click files or folders in the map to select them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Selections persist while you drill in and out.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func list(_ selected: [Node], root: String) -> some View {
        List(selected) { node in
            HStack(spacing: 8) {
                Image(systemName: node.isDir ? "folder.fill" : "doc.fill")
                    .foregroundStyle(node.isDir ? Color.accentColor : .secondary)
                    .frame(width: 16)

                Text(PathUtils.relativePath(node.path, to: root))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(node.path)

                Spacer(minLength: 6)

                Text(FileSizeFormatter.string(from: node.sizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    ScanManager.shared.toggleSelection(nodeID: node.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from selection")
            }
            .padding(.vertical, 1)
        }
    }

    private func footer(_ selected: [Node]) -> some View {
        let total = selected.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return VStack(spacing: 10) {
            HStack {
                Text("Total")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(FileSizeFormatter.string(from: total))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.subheadline)

            DeleteConfirmationView()
                .frame(maxWidth: .infinity)
        }
        .padding()
    }
}
