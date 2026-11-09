import SwiftUI
import Combine

/// Central observable state shared across the whole app.
/// Injected via .environmentObject so every view can read it.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Accounts
    @Published var accounts: [EmailAccount] = []
    @Published var selectedAccount: EmailAccount?

    // MARK: - Inbox
    @Published var threads: [EmailThread] = []
    @Published var selectedThread: EmailThread?

    // MARK: - Agent
    @Published var agentMessages: [AgentMessage] = []
    @Published var isAgentListening = false

    // MARK: - Batch
    @Published var selectedThreadIDs: Set<UUID> = []

    // MARK: - Navigation
    @Published var navigationPath = NavigationPath()
    @Published var showAgentPanel = false
    @Published var showAccountSetup = false

    // MARK: - Services (lazy singletons)
    let speech = SpeechService()
    let agent  = AIAgentService()

    // MARK: - Notifications
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadAccounts()
    }

    // MARK: - Account loading

    func loadAccounts() {
        accounts = AccountStore.shared.loadAll()
        selectedAccount = accounts.first
        if let first = selectedAccount {
            Task { await refreshInbox(for: first) }
        }
    }

    func addAccount(_ account: EmailAccount) {
        accounts.append(account)
        AccountStore.shared.save(accounts)
    }

    func removeAccount(_ account: EmailAccount) {
        accounts.removeAll { $0.id == account.id }
        AccountStore.shared.save(accounts)
        if selectedAccount?.id == account.id {
            selectedAccount = accounts.first
        }
    }

    // MARK: - Inbox

    func refreshInbox(for account: EmailAccount) async {
        let service = EmailServiceFactory.service(for: account)
        do {
            let fetched = try await service.fetchThreads(limit: 50)
            threads = fetched
        } catch {
            announce("Could not load inbox: \(error.localizedDescription)")
        }
    }

    // MARK: - Batch actions

    func deleteSelected() async {
        guard let account = selectedAccount else { return }
        let service = EmailServiceFactory.service(for: account)
        let ids = Array(selectedThreadIDs)
        do {
            try await service.deleteThreads(ids: ids)
            threads.removeAll { selectedThreadIDs.contains($0.id) }
            selectedThreadIDs.removeAll()
            announce("Deleted \(ids.count) emails.")
        } catch {
            announce("Delete failed: \(error.localizedDescription)")
        }
    }

    func archiveSelected() async {
        guard let account = selectedAccount else { return }
        let service = EmailServiceFactory.service(for: account)
        let ids = Array(selectedThreadIDs)
        do {
            try await service.archiveThreads(ids: ids)
            threads.removeAll { selectedThreadIDs.contains($0.id) }
            selectedThreadIDs.removeAll()
            announce("Archived \(ids.count) emails.")
        } catch {
            announce("Archive failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Accessibility announcements

    func announce(_ message: String) {
        NSAccessibility.post(element: NSApp, notification: .announcementRequested,
                             userInfo: [NSAccessibilityAnnouncementKey: message,
                                        NSAccessibilityPriorityKey: NSAccessibilityPriorityLevel.high.rawValue])
        speech.speak(message)
    }
}
