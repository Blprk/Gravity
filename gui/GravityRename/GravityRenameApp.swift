import SwiftUI

@main
struct GravityRenameApp: App {
    init() {
        // Force the app to focus and show in the Dock
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
