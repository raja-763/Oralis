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

    // MARK: - Calendar
    @Published var calendarSummary: String = ""

    // MARK: - Services
    let speech  = SpeechService()
    let agent   = AIAgentService()
    let browser = BrowserModel()

    // MARK: - Notifications
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadAccounts()
        Task { await loadCalendarSummary() }
        Task { await speech.requestPermissions() }  // trigger mic + speech dialogs on launch
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

    // MARK: - Calendar

    func loadCalendarSummary() async {
        let events = (try? await CalendarService.shared.upcomingEvents(days: 7)) ?? []
        calendarSummary = CalendarService.shared.formatEventSummary(events)
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
        isAgentListening = true
        let locale = speech.preferences.language
        speech.onFinalResult = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAgentListening = false
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.sendAgentMessage(text)
            }
        }
        Task {
            let ok = await speech.requestPermissions()
            guard ok else {
                isAgentListening = false
                readAloud("Microphone or speech recognition access denied. Please allow it in System Settings under Privacy and Security.")
                return
            }
            do {
                try speech.startListening(locale: locale)
            } catch {
                isAgentListening = false
                readAloud("Could not start listening: \(error.localizedDescription)")
            }
        }
    }

    func stopListening() {
        speech.stopListening()
        isAgentListening = false
    }

    func sendAgentMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        agentMessages.append(AgentMessage(role: .user, content: trimmed))

        let context = buildContext()
        Task {
            do {
                let response = try await agent.send(
                    userMessage: trimmed,
                    history: agentMessages.dropLast(),
                    context: context
                )
                // Strip the JSON action block from spoken text
                let spoken = responseTextWithoutJSON(response.text)
                agentMessages.append(AgentMessage(role: .assistant, content: spoken))
                readAloud(spoken)
                if let action = response.action {
                    await execute(action)
                }
            } catch OralisError.apiError(let msg) where msg.contains("No API key") {
                let prompt = "To use voice commands, please open Settings and add your Anthropic API key."
                agentMessages.append(AgentMessage(role: .assistant, content: prompt))
                readAloud(prompt)
            } catch {
                let errMsg = "Sorry, I ran into an error: \(error.localizedDescription)"
                agentMessages.append(AgentMessage(role: .assistant, content: errMsg))
                readAloud(errMsg)
            }
        }
    }

    // MARK: - Execute agent actions

    private func execute(_ action: AgentAction) async {
        switch action {

        // ── Email ─────────────────────────────────────────────────────────
        case .readEmail(let threadID):
            if let thread = threads.first(where: { $0.id.uuidString == threadID }),
               let msg = thread.messages.first {
                readAloud(msg.bodyPlain.isEmpty ? msg.subject : msg.bodyPlain)
            }

        case .summarize(let threadID):
            if let thread = threads.first(where: { $0.id.uuidString == threadID }),
               let msg = thread.messages.first {
                let body = msg.bodyPlain.isEmpty ? msg.subject : msg.bodyPlain
                sendAgentMessage("Please summarize this email:\n\(body.prefix(2000))")
            }

        case .triage:
            let unread = threads.filter { !$0.isRead }.count
            let top = threads.prefix(3).map { "\($0.subject) from \($0.participants.first?.display ?? "unknown")" }.joined(separator: "; ")
            readAloud("You have \(unread) unread emails. Top threads: \(top).")

        case .delete(let ids):
            selectedThreadIDs = Set(ids.compactMap { UUID(uuidString: $0) })
            await deleteSelected()

        case .archive(let ids):
            selectedThreadIDs = Set(ids.compactMap { UUID(uuidString: $0) })
            await archiveSelected()

        case .reply(let threadID, let body):
            guard let account = selectedAccount,
                  let thread = threads.first(where: { $0.id.uuidString == threadID }),
                  let msg = thread.messages.first
            else { return }
            let service = EmailServiceFactory.service(for: account)
            let draft = DraftMessage(
                to: [msg.from],
                subject: thread.subject.hasPrefix("Re:") ? thread.subject : "Re: \(thread.subject)",
                body: body,
                replyToMessageID: msg.remoteID
            )
            try? await service.sendMessage(draft)
            readAloud("Reply sent.")

        case .forward(let threadID, let toAddress, let body):
            guard let account = selectedAccount,
                  let thread = threads.first(where: { $0.id.uuidString == threadID }),
                  let msg = thread.messages.first
            else { return }
            let service = EmailServiceFactory.service(for: account)
            let draft = DraftMessage(
                to: [EmailAddress(name: "", address: toAddress)],
                subject: thread.subject.hasPrefix("Fwd:") ? thread.subject : "Fwd: \(thread.subject)",
                body: body,
                forwardOfMessageID: msg.remoteID
            )
            try? await service.sendMessage(draft)
            readAloud("Email forwarded to \(toAddress).")

        case .draft(let to, let subject, let body):
            guard let account = selectedAccount else { return }
            let service = EmailServiceFactory.service(for: account)
            let draft = DraftMessage(
                to: [EmailAddress(name: "", address: to)],
                subject: subject,
                body: body
            )
            try? await service.sendMessage(draft)
            readAloud("Draft saved. Subject: \(subject).")

        case .search(let query):
            guard let account = selectedAccount else { return }
            let service = EmailServiceFactory.service(for: account)
            threads = (try? await service.searchThreads(query: query)) ?? []
            readAloud("Found \(threads.count) results for '\(query)'.")

        case .unsubscribe(let threadID):
            guard let account = selectedAccount,
                  let thread = threads.first(where: { $0.id.uuidString == threadID }),
                  let msg = thread.messages.first
            else { return }
            let service = EmailServiceFactory.service(for: account)
            try? await service.unsubscribe(from: msg)
            readAloud("Unsubscribed.")

        case .deleteSpam:
            guard let account = selectedAccount else { return }
            let service = EmailServiceFactory.service(for: account)
            if let spamIDs = try? await service.fetchSpam(limit: 200).map({ $0.id.uuidString }) {
                selectedThreadIDs = Set(spamIDs.compactMap { UUID(uuidString: $0) })
                await deleteSelected()
            }

        // ── Calendar ─────────────────────────────────────────────────────
        case .listCalendar(let days):
            let events = (try? await CalendarService.shared.upcomingEvents(days: days)) ?? []
            let summary = CalendarService.shared.formatEventSummary(events)
            agentMessages.append(AgentMessage(role: .assistant, content: summary))
            readAloud(summary)

        case .createEvent(let title, let dateStr, let duration):
            let eventDate = parseDate(dateStr) ?? Date().addingTimeInterval(3600)
            do {
                try await CalendarService.shared.createEvent(title: title, startDate: eventDate, durationMinutes: duration)
                readAloud("Event '\(title)' added to your calendar.")
            } catch {
                readAloud("Could not create the event: \(error.localizedDescription)")
            }

        case .acceptInvite(let threadID):
            guard let thread = threads.first(where: { $0.id.uuidString == threadID }),
                  let invite = thread.messages.first?.calendarInvite
            else { return }
            try? await CalendarService.shared.addInvite(invite)
            readAloud("Invite accepted and added to your calendar.")

        case .declineInvite:
            readAloud("Invite declined.")

        // ── Browser ──────────────────────────────────────────────────────
        case .navigateTo(let url):
            browser.navigate(to: url.absoluteString)
            readAloud("Navigating to \(url.host ?? url.absoluteString).")

        case .readWebPage:
            browser.readPageText { [weak self] text in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let preview = String(text.prefix(3000))
                    if preview.isEmpty {
                        self.readAloud("The page appears to be empty or hasn't loaded yet.")
                    } else {
                        self.agentMessages.append(AgentMessage(role: .assistant, content: preview))
                        self.readAloud(preview)
                    }
                }
            }

        case .fillWebForm(let field, let value):
            browser.fillForm(fieldHint: field, value: value)
            readAloud("Filled in '\(field)' with '\(value)'.")

        case .clickElement(let text):
            browser.clickElement(text: text)
            readAloud("Clicked '\(text)'.")

        case .scrollDown:
            browser.scrollDown()

        case .goBack:
            browser.goBack()
            readAloud("Going back.")

        case .openLink(let url):
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func buildContext() -> EmailAgentContext {
        EmailAgentContext(
            inboxSummary: inboxSummary(),
            selectedThread: selectedThread,
            webPageURL: browser.currentURL,
            webPageContent: browser.pageText.isEmpty ? nil : String(browser.pageText.prefix(2000)),
            calendarSummary: calendarSummary.isEmpty ? nil : calendarSummary
        )
    }

    private func inboxSummary() -> String {
        guard !threads.isEmpty else { return "The inbox is empty." }
        let unread = threads.filter { !$0.isRead }.count
        let preview = threads.prefix(5)
            .map { "- \($0.subject) from \($0.participants.first?.display ?? "unknown")" }
            .joined(separator: "\n")
        return "Inbox: \(threads.count) threads, \(unread) unread.\nRecent:\n\(preview)"
    }

    private func responseTextWithoutJSON(_ text: String) -> String {
        guard let start = text.range(of: "{"),
              let end   = text.range(of: "}", options: .backwards),
              start.lowerBound < end.upperBound
        else { return text }
        var result = text
        result.removeSubrange(start.lowerBound...end.upperBound)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        for f in ["yyyy-MM-dd HH:mm", "MM/dd/yyyy HH:mm", "MMMM d, yyyy HH:mm"] {
            fmt.dateFormat = f
            if let d = fmt.date(from: s) { return d }
        }
        return nil
    }

    // MARK: - Accessibility announcements

    func announce(_ message: String) {
        // Route through Oralis's own TTS instead of NSAccessibility/VoiceOver.
        // Using .announcementRequested on macOS 27 triggers VoiceOver which speaks
        // over Oralis's own TTS and can cause the accessibility label recursion crash.
        readAloud(message)
    }

    func readAloud(_ message: String) {
        speech.speak(message)
    }
}
