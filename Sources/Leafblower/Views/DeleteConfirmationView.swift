import SwiftUI

struct DeleteConfirmationView: View {
    @State private var showConfirmation = false

    var body: some View {
        let count = ScanManager.shared.selectedNodeIDs.count
        Button(role: .destructive) {
            showConfirmation = true
        } label: {
            Label(count > 0 ? "Delete \(count) Item\(count == 1 ? "" : "s")" : "Delete Selected",
                  systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.red)
        .disabled(count == 0)
        .alert("Delete \(count) item\(count == 1 ? "" : "s")?", isPresented: $showConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await ScanManager.shared.deleteSelected()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected files and folders will be permanently deleted from disk. This cannot be undone.")
        }
    }
}
