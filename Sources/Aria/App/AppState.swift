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
    @Published var showIMAPSetup = false

    // MARK: - Onboarding
    @Published var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "oralis.onboardingComplete")

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

    // MARK: - Voice + Agent (Talk screen)

    func startListening() {
        guard selectedAccount != nil else {
            announce("No email account connected. Open Settings to add one.")
            return
        }
        isAgentListening = true
        speech.onFinalResult = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAgentListening = false
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.sendAgentMessage(text)
            }
        }
        try? speech.startListening()
    }

    func stopListening() {
        speech.stopListening()
        isAgentListening = false
    }

    func sendAgentMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMsg = AgentMessage(role: .user, content: trimmed)
        agentMessages.append(userMsg)

        let context = EmailAgentContext(
            inboxSummary: inboxSummary(),
            selectedThread: selectedThread
        )
        Task {
            do {
                let response = try await agent.send(
                    userMessage: trimmed,
                    history: agentMessages.dropLast(),
                    context: context
                )
                let reply = AgentMessage(role: .assistant, content: response.text)
                agentMessages.append(reply)
                if let action = response.action {
                    await execute(action)
                }
            } catch {
                agentMessages.append(AgentMessage(role: .assistant,
                    content: "Sorry, I ran into an error: \(error.localizedDescription)"))
            }
        }
    }

    private func inboxSummary() -> String {
        guard !threads.isEmpty else { return "The inbox is empty." }
        let unread = threads.filter { !$0.isRead }.count
        let preview = threads.prefix(5).map { "- \($0.subject) from \($0.participants.first?.display ?? "unknown")" }.joined(separator: "\n")
        return "Inbox: \(threads.count) threads, \(unread) unread.\nRecent:\n\(preview)"
    }

    private func execute(_ action: AgentAction) async {
        switch action {
        case .delete(let ids):
            selectedThreadIDs = Set(ids.compactMap { UUID(uuidString: $0) })
            await deleteSelected()
        case .archive(let ids):
            selectedThreadIDs = Set(ids.compactMap { UUID(uuidString: $0) })
            await archiveSelected()
        case .deleteSpam:
            guard let account = selectedAccount else { return }
            let service = EmailServiceFactory.service(for: account)
            if let spamIDs = try? await service.fetchSpam(limit: 200).map({ $0.id.uuidString }) {
                selectedThreadIDs = Set(spamIDs.compactMap { UUID(uuidString: $0) })
                await deleteSelected()
            }
        case .search(let query):
            guard let account = selectedAccount else { return }
            let service = EmailServiceFactory.service(for: account)
            threads = (try? await service.searchThreads(query: query)) ?? []
        case .openLink(let url):
            NSWorkspace.shared.open(url)
        case .unsubscribe(let threadID):
            guard let account = selectedAccount,
                  let thread = threads.first(where: { $0.id.uuidString == threadID }),
                  let msg = thread.messages.first
            else { return }
            let service = EmailServiceFactory.service(for: account)
            try? await service.unsubscribe(from: msg)
            announce("Unsubscribed.")
        default:
            break
        }
    }

    // MARK: - Accessibility announcements

    // Posts to VoiceOver only. TTS is only used when the user explicitly
    // requests read-aloud (email detail view, voice command responses).
    func announce(_ message: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: message,
                                        NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    // Call this only for explicit user-requested read-aloud.
    func readAloud(_ message: String) {
        speech.speak(message)
    }
}
