import SwiftUI

struct ContentView: View {
    @Environment(ScanManager.self) private var scanManager

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                VStack(spacing: 0) {
                    PathBarView()
                    Divider()
                    BreadcrumbView()
                        .padding(.vertical, 6)
                    Divider()
                    TreemapView()
                }
                .frame(minWidth: 480)

                SelectionPanel()
                    .frame(minWidth: 250, idealWidth: 300)
                    .frame(maxWidth: 400)
            }

            Divider()
            StatusBarView()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    scanManager.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!scanManager.canRescan)

                Button("Clear") {
                    scanManager.clearSelection()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(scanManager.selectedNodeIDs.isEmpty || scanManager.isDeleting)
            }
        }
    }
}
