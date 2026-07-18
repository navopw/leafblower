import SwiftUI

struct PathBarView: View {
    @Environment(ScanManager.self) private var scanManager
    @State private var path = "~"

    private var isScanning: Bool {
        scanManager.isScanning
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Path (e.g. ~/Downloads)", text: $path)
                .textFieldStyle(.roundedBorder)
                .onSubmit(startScan)

            Button {
                if let url = NSOpenPanelUtils.selectDirectory() {
                    path = url.path
                }
            } label: {
                Label("Browse", systemImage: "folder")
            }

            Button(action: startScan) {
                let isStopping = scanManager.currentJob?.status == .cancelling
                Label(isStopping ? "Stopping..." : (isScanning ? "Scanning..." : "Scan"),
                      systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!scanManager.canStartScan || path.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                if let job = scanManager.currentJob {
                    scanManager.cancelScan(id: job.id)
                }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!isScanning)
        }
        .padding(10)
    }

    private func startScan() {
        guard !isScanning else { return }
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        scanManager.startScan(rootPath: trimmed, includeHidden: true)
    }
}
