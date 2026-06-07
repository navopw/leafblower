import SwiftUI

@main
struct LeafblowerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
    }
}
