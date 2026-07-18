import SwiftUI

struct BreadcrumbView: View {
    @Environment(ScanManager.self) private var scanManager

    var body: some View {
        if let job = scanManager.currentJob {
            let components = buildBreadcrumb(job: job)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 2)

                    ForEach(components.indices, id: \.self) { i in
                        let component = components[i]
                        let isLast = i == components.count - 1

                        Button(component.name) {
                            scanManager.zoomInto(nodeID: component.id)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isLast ? Color.primary : Color.accentColor)
                        .fontWeight(isLast ? .semibold : .regular)
                        .disabled(isLast)

                        if !isLast {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func buildBreadcrumb(job: ScanJob) -> [(id: String, name: String)] {
        var components: [(id: String, name: String)] = []
        var currentID: String? = scanManager.currentZoomNodeID

        while let id = currentID, let node = job.nodeIndex[id] {
            components.insert((id: node.id, name: node.name), at: 0)
            currentID = node.parentID
        }

        return components
    }
}
