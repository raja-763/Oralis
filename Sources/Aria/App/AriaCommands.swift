import SwiftUI

/// Menu-bar commands so every feature is reachable by keyboard.
struct OralisCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Email Account…") {
                appState.showAccountSetup = true
            }
            .keyboardShortcut("N", modifiers: [.command, .shift])

            Divider()

            Button("Toggle AI Agent") {
                appState.showAgentPanel.toggle()
            }
            .keyboardShortcut("A", modifiers: [.command, .option])

            Button("Start Listening") {
                appState.isAgentListening.toggle()
            }
            .keyboardShortcut("L", modifiers: [.command, .option])
        }

        CommandGroup(after: .pasteboard) {
            Button("Delete Selected (\(appState.selectedThreadIDs.count))") {
                Task { await appState.deleteSelected() }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(appState.selectedThreadIDs.isEmpty)

            Button("Archive Selected (\(appState.selectedThreadIDs.count))") {
                Task { await appState.archiveSelected() }
            }
            .keyboardShortcut("E", modifiers: .command)
            .disabled(appState.selectedThreadIDs.isEmpty)

            Button("Select All") {
                appState.selectedThreadIDs = Set(appState.threads.map(\.id))
            }
            .keyboardShortcut("A", modifiers: .command)
        }
    }
}
