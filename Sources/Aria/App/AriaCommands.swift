import SwiftUI

/// Full macOS menu bar for Oralis — shown when the app is frontmost.
/// Gives VoiceOver users (and power users) keyboard access to every feature.
struct OralisCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        oralisMenu
        emailMenu
        voiceMenu
        helpMenu
    }

    // MARK: - Oralis menu (replaces the default "File" group)

    private var oralisMenu: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Email Account…") {
                appState.showAccountSetup = true
            }
            .keyboardShortcut("N", modifiers: [.command, .shift])

            Button("Add IMAP Account…") {
                appState.showIMAPSetup = true
            }

            Divider()

            Button("Settings…") {
                NotificationCenter.default.post(name: .oralisOpenSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    // MARK: - Email menu

    private var emailMenu: some Commands {
        CommandMenu("Email") {
            Button("Refresh Inbox") {
                if let acc = appState.selectedAccount {
                    Task { await appState.refreshInbox(for: acc) }
                }
            }
            .keyboardShortcut("R", modifiers: .command)

            Divider()

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

            Divider()

            Button("Select All") {
                appState.selectedThreadIDs = Set(appState.threads.map(\.id))
            }
            .keyboardShortcut("A", modifiers: .command)

            Button("Deselect All") {
                appState.selectedThreadIDs.removeAll()
            }
            .keyboardShortcut("D", modifiers: .command)

            Divider()

            Button("Ask Oralis to Summarize Inbox") {
                appState.sendAgentMessage("Give me a summary of my inbox.")
            }
            .keyboardShortcut("I", modifiers: [.command, .option])

            Button("Ask Oralis to Delete Spam") {
                appState.sendAgentMessage("Delete all spam and junk emails.")
            }
        }
    }

    // MARK: - Voice menu

    private var voiceMenu: some Commands {
        CommandMenu("Voice") {
            Button("Toggle Menu Bar Panel") {
                NotificationCenter.default.post(name: .oralisTogglePanel, object: nil)
            }
            .keyboardShortcut("O", modifiers: [.command, .option])

            Divider()

            Button(appState.isConversationMode ? "End Conversation" : "Start Conversation") {
                if appState.isConversationMode {
                    appState.stopConversationMode()
                } else {
                    appState.startConversationMode()
                }
            }
            .keyboardShortcut("L", modifiers: [.command, .option])

            Divider()

            Button("What's on my calendar today?") {
                appState.sendAgentMessage("What's on my calendar today?")
            }
            .keyboardShortcut("K", modifiers: [.command, .option])

            Button("How many unread emails?") {
                appState.sendAgentMessage("How many unread emails do I have?")
            }

            Divider()

            Button("Stop Speaking") {
                appState.speech.stopSpeaking()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!appState.speech.isSpeaking)
        }
    }

    // MARK: - Help menu additions

    private var helpMenu: some Commands {
        CommandGroup(after: .help) {
            Divider()

            Button("Wake Word: Say \"Oralis\"") { }
                .disabled(true)

            Button("Global Hotkey: Option+Space") { }
                .disabled(true)

            Divider()

            Button("Open Anthropic Console…") {
                NSWorkspace.shared.open(URL(string: "https://console.anthropic.com")!)
            }

            Button("Voice Settings…") {
                NotificationCenter.default.post(name: .oralisOpenSettings, object: nil)
            }
        }
    }
}
