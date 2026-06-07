import SwiftUI

struct DeleteConfirmationView: View {
    @State private var showConfirmation = false

    var body: some View {
        Button("Delete Selected", role: .destructive) {
            showConfirmation = true
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .alert("Confirm Deletion", isPresented: $showConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await ScanManager.shared.deleteSelected()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently delete \(ScanManager.shared.selectedNodeIDs.count) item(s)? This cannot be undone.")
        }
    }
}
