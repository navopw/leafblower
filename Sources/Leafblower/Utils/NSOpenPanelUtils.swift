import AppKit

enum NSOpenPanelUtils {
    @MainActor
    static func selectDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }
}
