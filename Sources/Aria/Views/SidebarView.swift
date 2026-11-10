import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedAccount?.id },
            set: { id in
                appState.selectedAccount = appState.accounts.first { $0.id == id }
                if let acc = appState.selectedAccount {
                    Task { await appState.refreshInbox(for: acc) }
                }
            }
        )) {
            Section("Accounts") {
                ForEach(appState.accounts) { account in
                    Label(account.displayName, systemImage: account.provider.iconName)
                        .tag(account.id)
                        .accessibilityLabel(account.accessibilityLabel)
                        .contextMenu {
                            Button("Remove Account", role: .destructive) {
                                appState.removeAccount(account)
                            }
                        }
                }

                Button {
                    appState.showAccountSetup = true
                } label: {
                    Label("Add Account…", systemImage: "plus.circle")
                }
                .accessibilityLabel("Add a new email account")
            }

            Section("Folders") {
                Label("Inbox", systemImage: "tray.fill")
                    .accessibilityLabel("Inbox, \(appState.threads.filter { !$0.isRead }.count) unread")
                Label("Spam", systemImage: "xmark.bin.fill")
                Label("Sent", systemImage: "paperplane.fill")
                Label("Archive", systemImage: "archivebox.fill")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Oralis")
        .accessibilityLabel("Accounts and folders")
    }
}
