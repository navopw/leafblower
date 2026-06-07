import SwiftUI

struct PathBarView: View {
    @State private var path = "~"

    private var isScanning: Bool {
        let status = ScanManager.shared.currentJob?.status
        return status == .running || status == .queued
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
                Label(isScanning ? "Scanning…" : "Scan", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(isScanning || path.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                if let job = ScanManager.shared.currentJob {
                    ScanManager.shared.cancelScan(id: job.id)
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
        ScanManager.shared.startScan(rootPath: trimmed, includeHidden: false)
    }
}
