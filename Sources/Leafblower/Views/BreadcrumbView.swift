import SwiftUI

struct BreadcrumbView: View {
    var body: some View {
        if let job = ScanManager.shared.currentJob {
            let components = buildBreadcrumb(job: job)
            HStack(spacing: 4) {
                ForEach(components.indices, id: \.self) { i in
                    let component = components[i]
                    Button(component.name) {
                        ScanManager.shared.currentZoomNodeID = component.id
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)

                    if i < components.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func buildBreadcrumb(job: ScanJob) -> [(id: String, name: String)] {
        var components: [(id: String, name: String)] = []
        var currentID: String? = ScanManager.shared.currentZoomNodeID

        while let id = currentID, let node = job.nodeIndex[id] {
            components.insert((id: node.id, name: node.name), at: 0)
            currentID = node.parentID
        }

        return components
    }
}
