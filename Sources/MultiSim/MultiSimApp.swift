import SwiftUI

@main
struct MultiSimApp: App {
    var body: some Scene {
        WindowGroup("MULTIMACSIM.v1 — B.Tech Year 1 Electrical Edition") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }
    }
}
