import SwiftUI

@main
struct MultiSimApp: App {
    @StateObject private var viewModel = CircuitEditorViewModel()

    var body: some Scene {
        WindowGroup("MULTIMACSIM") {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Circuit") { viewModel.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { viewModel.openDocument() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Save") { viewModel.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { viewModel.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
