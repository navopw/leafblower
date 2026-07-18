import SwiftUI

struct DeleteConfirmationView: View {
    @Environment(ScanManager.self) private var scanManager
    @State private var showConfirmation = false
    @State private var showFailure = false
    @State private var failureMessage = ""

    var body: some View {
        let selected = scanManager.selectedNodes
        let count = selected.count
        let total = selected.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let containsIncompleteFolder = selected.contains { $0.isDir && !$0.isScanComplete }
        let containsMountPoint = selected.contains(where: \.isMountPoint)

        Button(role: .destructive) {
            showConfirmation = true
        } label: {
            if scanManager.isDeleting {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Moving to Trash...")
                }
                .frame(maxWidth: .infinity)
            } else {
                Label(
                    count > 0 ? "Move \(count) Item\(count == 1 ? "" : "s") to Trash" : "Move to Trash",
                    systemImage: "trash"
                )
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.red)
        .disabled(count == 0 || scanManager.isDeleting || containsIncompleteFolder || containsMountPoint)
        .help(blockedHelp(
            containsIncompleteFolder: containsIncompleteFolder,
            containsMountPoint: containsMountPoint
        ))
        .alert("Move \(count) item\(count == 1 ? "" : "s") to Trash?", isPresented: $showConfirmation) {
            Button("Move to Trash", role: .destructive) {
                Task {
                    let response = await scanManager.deleteSelected()
                    if !response.failed.isEmpty {
                        failureMessage = failureDescription(response.failed)
                        showFailure = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(FileSizeFormatter.string(from: total)) will be moved to Trash and can be recovered until Trash is emptied.")
        }
        .alert("Some items could not be moved", isPresented: $showFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage)
        }
    }

    private func failureDescription(_ failures: [DeleteResult]) -> String {
        let details = failures.prefix(3).map { failure in
            let name = failure.path.isEmpty
                ? failure.nodeID
                : (failure.path as NSString).lastPathComponent
            return "\(name): \(failure.error ?? "Unknown error")"
        }
        let remaining = failures.count - details.count
        if remaining > 0 {
            return (details + ["and \(remaining) more..."]).joined(separator: "\n")
        }
        return details.joined(separator: "\n")
    }

    private func blockedHelp(containsIncompleteFolder: Bool, containsMountPoint: Bool) -> String {
        if containsMountPoint { return "Mounted volume roots cannot be moved" }
        if containsIncompleteFolder {
            return "Incomplete folders must be rescanned before they can be moved"
        }
        return "Move the selection to Trash"
    }
}
