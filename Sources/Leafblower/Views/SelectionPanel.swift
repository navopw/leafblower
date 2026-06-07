import SwiftUI

struct SelectionPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Selection")
                .font(.headline)
                .padding()

            Divider()

            if let job = ScanManager.shared.currentJob {
                let selected = ScanManager.shared.selectedNodeIDs.compactMap { job.nodeIndex[$0] }

                List(selected) { node in
                    HStack {
                        Image(systemName: node.isDir ? "folder" : "doc")
                        Text(node.name)
                        Spacer()
                        Text(FileSizeFormatter.string(from: node.sizeBytes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(selected.count) item(s)")
                        .font(.subheadline)
                    Text("Total: \(FileSizeFormatter.string(from: selected.reduce(0) { $0 + $1.sizeBytes }))")
                        .font(.headline)
                }
                .padding()
            }

            Spacer()
        }
        .frame(minWidth: 250)
        .background(Color(.windowBackgroundColor))
    }
}
