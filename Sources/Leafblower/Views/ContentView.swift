import SwiftUI

struct ContentView: View {
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
                    ScanManager.shared.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(ScanManager.shared.currentJob == nil)

                Button("Clear") {
                    ScanManager.shared.clearSelection()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(ScanManager.shared.selectedNodeIDs.isEmpty)
            }
        }
    }
}
