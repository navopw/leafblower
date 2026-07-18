import SwiftUI

@main
struct LeafblowerApp: App {
    @State private var scanManager = ScanManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(scanManager)
                .frame(minWidth: 820, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
    }
}
