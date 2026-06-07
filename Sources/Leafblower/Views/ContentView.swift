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
            ToolbarItem {
                Button("Clear") {
                    ScanManager.shared.clearSelection()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(ScanManager.shared.selectedNodeIDs.isEmpty)
            }
        }
    }
}
