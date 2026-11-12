import AppKit
import EventKit
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
    private var spamThreads: [EmailThread] = []
    private var isLoadingInbox = false

    private static func senderName(_ t: EmailThread) -> String {
        guard let sender = t.participants.first else { return "unknown" }
        // Spoken form: the display name only, without the address in angle brackets.
        var name = sender.name.isEmpty ? sender.address : sender.name
        if let bracket = name.firstIndex(of: "<"), bracket > name.startIndex {
            name = String(name[..<bracket])
        }
        name = name.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "unknown" : name
    }
    private var inboxProblem: String?
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

    // MARK: - Conversation mode
    @Published var isConversationMode = false
    @Published var isProcessingResponse = false   // true while awaiting AI reply
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?

    // MARK: - Notifications
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadAccounts()
        // Each permission is requested only when its feature is first used, never at
        // launch. The calendar is read here only if access was already granted.
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            Task { await loadCalendarSummary() }
        }
        Task {
            let ok = await speech.requestPermissions()
            if ok {
                speech.onWakeWordDetected = { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        NSApp.activate(ignoringOtherApps: true)
                        self.startConversationMode()
                    }
                }
                // Skip wake word detection when VoiceOver is running — the continuous
                // audio session conflicts with VoiceOver's audio and causes "not responding".
                // VoiceOver users use the button or Option+Space instead.
                if !SpeechService.isVoiceOverActive {
                    speech.startWakeWordDetection()
                }
            }
        }
        setupConversationLoop()
        registerGlobalHotkey()
    }

    // Auto-restart listening after Oralis finishes speaking (conversation mode)
    private func setupConversationLoop() {
        speech.$isSpeaking
            .combineLatest($isConversationMode, $isAgentListening, $isProcessingResponse)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] speaking, conversing, listening, processing in
                guard let self, !speaking, conversing, !listening, !processing else { return }
                self.startListening()
            }
            .store(in: &cancellables)
    }

    // Global hotkey: Option+Space activates Oralis from anywhere on the Mac
    private func registerGlobalHotkey() {
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Option+Space (keyCode 49)
            guard event.keyCode == 49, event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.interruptOrToggleConversation()
            }
        }
        // Same key while Oralis itself is the front app.
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 49, event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift) else { return event }
            Task { @MainActor [weak self] in self?.interruptOrToggleConversation() }
            return nil
        }
    }

    // MARK: - Conversation mode control

    /// Option+Space: while Oralis is talking in a conversation, cut it off and listen
    /// right away; otherwise start or end the conversation.
    func interruptOrToggleConversation() {
        if isConversationMode && speech.isSpeaking {
            speech.stopSpeaking()
        } else if isConversationMode {
            stopConversationMode()
        } else {
            startConversationMode()
        }
    }

    func startConversationMode() {
        guard !isConversationMode else { return }
        // No spoken greeting: the conversation loop opens the microphone at once and
        // the listening chime is the cue to speak.
        isConversationMode = true
    }

    func stopConversationMode() {
        isConversationMode = false
        stopListening()
        NSSound(named: .init("Pop"))?.play()
        readAloud("Okay, I'll stop listening.")
    }

    // Calendar permission with voice guidance — skips if already granted
    func requestCalendarAccessWithGuidance() async {
        let current = EKEventStore.authorizationStatus(for: .event)
        // Already granted — nothing to do
        if current == .fullAccess || current == .authorized { return }
        // Denied before — just open Settings silently
        if current == .denied || current == .restricted {
            readAloud("Calendar access is blocked. I'll open System Settings so you can enable it.")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            return
        }
        // Not determined — ask, with voice guidance so VoiceOver user knows what's coming
        readAloud("Oralis needs calendar access. A dialog will appear — press Return to allow.")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let store = EKEventStore()
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = await (try? store.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
            }
        }
        if granted {
            readAloud("Calendar access granted.")
        } else {
            readAloud("Calendar access was denied. Opening System Settings so you can enable it.")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
        }
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
        // Signing in again with the same address replaces the old entry and its stale login.
        for old in accounts where old.emailAddress.lowercased() == account.emailAddress.lowercased() {
            KeychainService.shared.delete(key: "oauth.access.\(old.id)")
            KeychainService.shared.delete(key: "oauth.refresh.\(old.id)")
            KeychainService.shared.delete(key: "oauth.expiry.\(old.id)")
        }
        accounts.removeAll { $0.emailAddress.lowercased() == account.emailAddress.lowercased() }
        accounts.append(account)
        AccountStore.shared.save(accounts)
        selectedAccount = account
        Task { await refreshInbox(for: account) }
    }

    func removeAccount(_ account: EmailAccount) {
        accounts.removeAll { $0.id == account.id }
        AccountStore.shared.save(accounts)
        if selectedAccount?.id == account.id {
            selectedAccount = accounts.first
        }
    }

    // MARK: - Inbox

    func refreshInbox(for account: EmailAccount, attempt: Int = 1) async {
        let service = EmailServiceFactory.service(for: account)
        oralisLog("inbox: load started (attempt \(attempt))")
        isLoadingInbox = true
        defer { isLoadingInbox = false }
        do {
            // Newest few first so the inbox is usable within seconds, then the rest.
            if threads.isEmpty {
                let first = try await service.fetchThreads(limit: 5)
                if !first.isEmpty { threads = first }
                oralisLog("inbox: first \(first.count) threads ready")
            }
            let fetched = try await service.fetchThreads(limit: 25)
            threads = fetched
            inboxProblem = nil
            oralisLog("inbox: loaded \(fetched.count) threads")
        } catch {
            let detail = String(describing: error)
            oralisLog("inbox: load failed: \(detail.prefix(300))")
            if detail.contains("Quota exceeded") || detail.contains("rateLimitExceeded") {
                // Google's per-minute limit: wait quietly and try again.
                if attempt < 4 {
                    inboxProblem = nil
                    try? await Task.sleep(nanoseconds: 25_000_000_000)
                    await refreshInbox(for: account, attempt: attempt + 1)
                } else {
                    inboxProblem = "Gmail is temporarily limiting requests. It usually clears within a minute or two."
                    announce("Gmail is busy right now. Please ask again in a minute.")
                }
            } else if detail.contains("insufficient authentication scopes") {
                inboxProblem = "Google has not given Oralis permission to read mail; the account must be added again in Settings."
                announce("Oralis is signed in to Google but was not given permission to read your mail. Open Settings, add the account again, and allow Gmail access on Google's page.")
            } else if case OralisError.notAuthenticated = error {
                inboxProblem = "The Google sign-in has expired; the account must be added again in Settings."
                announce("Your Google sign-in has expired. Open Settings and add the account again.")
            } else {
                inboxProblem = "The mail server could not be reached."
                announce("I could not load your inbox. Please check your internet connection and try again.")
            }
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
            guard !ids.isEmpty else { announce("I couldn't tell which email you meant."); return }
            try await service.deleteThreads(ids: ids)
            threads.removeAll { selectedThreadIDs.contains($0.id) }
            spamThreads.removeAll { selectedThreadIDs.contains($0.id) }
            selectedThreadIDs.removeAll()
            announce(ids.count == 1 ? "Moved it to the trash." : "Moved \(ids.count) emails to the trash.")
        } catch {
            oralisLog("delete failed: \(String(describing: error).prefix(200))")
            announce("Delete failed. \(error.localizedDescription)")
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
        // Pause wake word so both engines don't fight over the mic
        speech.stopWakeWordDetection()
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
        // Reset isAgentListening when mic stops for any reason (timeout, error, silence)
        speech.onListeningStopped = { [weak self] in
            Task { @MainActor [weak self] in
                self?.isAgentListening = false
            }
        }
        Task {
            // If already granted skip the dialog round-trip for speed.
            let ok = speech.permissionsGranted ? true : await speech.requestPermissions()
            guard ok else {
                isAgentListening = false
                readAloud("Microphone access is blocked. Go to System Settings, Privacy and Security, Microphone, and enable Oralis.")
                return
            }
            do {
                try await speech.startListening(locale: locale)
            } catch {
                isAgentListening = false
                readAloud("Could not start the microphone: \(error.localizedDescription)")
            }
        }
    }

    func stopListening() {
        speech.stopListening()
        isAgentListening = false
        // Resume wake word detection — but never when VoiceOver is running
        if speech.permissionsGranted && !speech.isWakeWordActive && !SpeechService.isVoiceOverActive {
            speech.startWakeWordDetection()
        }
    }

    func sendAgentMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Stop word detection — end conversation mode on explicit dismissal
        let lower = trimmed.lowercased()
        let stopWords = ["stop listening", "stop", "goodbye", "bye", "that's all", "exit", "quit", "oralis stop", "done"]
        if stopWords.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
            stopConversationMode()
            return
        }

        // "Heard you" tone — confirms STT captured the request
        NSSound(named: .init("Tink"))?.play()

        agentMessages.append(AgentMessage(role: .user, content: trimmed))


        let prefs = speech.preferences
        let context = buildContext()
        isProcessingResponse = true
        oralisLog("command: received (\(trimmed.count) characters), asking AI")
        // Soft tick every two seconds so it is audible that Oralis is still thinking.
        let thinkingTicks = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                NSSound(named: .init("Tink"))?.play()
            }
        }
        Task {
            defer { isProcessingResponse = false; thinkingTicks.cancel() }
            do {
                // Inject response-length hint into the user message when set to short
                let userMsg = prefs.responseLength == .short
                    ? "\(trimmed)\n\n(Reply in 1-2 sentences.)"
                    : trimmed
                let response = try await agent.send(
                    userMessage: userMsg,
                    history: agentMessages.dropLast(),
                    context: context
                )
                thinkingTicks.cancel()
                oralisLog("command: AI answered")
                // Response-ready tone — plays just before Oralis speaks the answer
                NSSound(named: .init("Glass"))?.play()

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
                oralisLog("command: AI failed: \(String(describing: error).prefix(200))")
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
                let prefs = speech.preferences
                if prefs.readEmailSummaryOnly {
                    // Ask AI for a summary instead of reading the full body
                    let body = msg.bodyPlain.isEmpty ? msg.subject : msg.bodyPlain
                    sendAgentMessage("Summarize this email in one sentence:\n\(body.prefix(2000))")
                } else {
                    let parts = emailReadParts(thread: thread, msg: msg, prefs: prefs)
                    readAloud(parts)
                }
            } else {
                oralisLog("readEmail: no thread matches the ID the AI gave")
                readAloud("I couldn't find that email. Ask me for your latest emails and pick one.")
            }

        case .summarize(let threadID):
            if let thread = threads.first(where: { $0.id.uuidString == threadID }),
               let msg = thread.messages.first {
                let body = msg.bodyPlain.isEmpty ? msg.subject : msg.bodyPlain
                sendAgentMessage("Please summarize this email in 2-3 sentences:\n\(body.prefix(2000))")
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

        case .sendText(let to, let body):
            guard !to.isEmpty, !body.isEmpty else {
                readAloud("I need both a recipient and a message to send a text.")
                return
            }
            do {
                let recipient = try await TextMessageService.resolve(to)
                try TextMessageService.send(body, to: recipient)
                oralisLog("text: sent")
                readAloud("Text sent to \(recipient.name).")
            } catch {
                oralisLog("text: failed: \(error.localizedDescription)")
                readAloud(error.localizedDescription)
            }

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

        case .listSpam:
            guard let account = selectedAccount else { return }
            let service = EmailServiceFactory.service(for: account)
            do {
                spamThreads = try await service.fetchSpam(limit: 15)
                let spoken: String
                if spamThreads.isEmpty {
                    spoken = "Your spam folder is empty."
                } else {
                    let lines = spamThreads.prefix(5).enumerated().map { index, t in
                        "\(index + 1), from \(Self.senderName(t)): \(t.subject)."
                    }.joined(separator: " ")
                    let count = spamThreads.count == 15 ? "at least 15" : "\(spamThreads.count)"
                    spoken = "You have \(count) emails in spam. \(lines) You can ask me to delete any of them, or to empty the spam folder."
                }
                agentMessages.append(AgentMessage(role: .assistant, content: spoken))
                readAloud(spoken)
            } catch {
                oralisLog("spam: list failed: \(String(describing: error).prefix(200))")
                readAloud("I couldn't open your spam folder. Please try again in a moment.")
            }

        case .markSpam(let ids):
            guard let account = selectedAccount else { return }
            let uuids = ids.compactMap { UUID(uuidString: $0) }
            guard !uuids.isEmpty else { readAloud("I couldn't tell which email you meant."); return }
            do {
                try await EmailServiceFactory.service(for: account).moveToSpam(ids: uuids)
                threads.removeAll { uuids.contains($0.id) }
                readAloud(uuids.count == 1 ? "Moved it to spam." : "Moved \(uuids.count) emails to spam.")
            } catch {
                oralisLog("spam: mark failed: \(String(describing: error).prefix(200))")
                readAloud("I couldn't move that to spam. \(error.localizedDescription)")
            }

        case .deleteSpam:
            guard let account = selectedAccount else { return }
            let service = EmailServiceFactory.service(for: account)
            do {
                let spam = try await service.fetchSpam(limit: 100)
                guard !spam.isEmpty else { readAloud("Your spam folder is already empty."); return }
                try await service.deleteThreads(ids: spam.map(\.id))
                spamThreads = []
                readAloud("Moved \(spam.count) spam emails to the trash.")
            } catch {
                oralisLog("spam: empty failed: \(String(describing: error).prefix(200))")
                readAloud("I couldn't empty the spam folder. \(error.localizedDescription)")
            }

        // ── Calendar ─────────────────────────────────────────────────────
        case .listCalendar(let days):
            await requestCalendarAccessWithGuidance()
            let events = (try? await CalendarService.shared.upcomingEvents(days: days)) ?? []
            let summary = CalendarService.shared.formatEventSummary(events)
            agentMessages.append(AgentMessage(role: .assistant, content: summary))
            readAloud(summary)

        case .createEvent(let title, let dateStr, let duration):
            await requestCalendarAccessWithGuidance()
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
        if let inboxProblem { return "The inbox could not be loaded, so its contents are unknown. Reason: \(inboxProblem) Tell the user this; do not say the inbox is empty." }
        if isLoadingInbox && threads.isEmpty { return "The inbox is still loading. Tell the user to ask again in a few seconds; do not say it is empty." }
        guard !threads.isEmpty else { return "The inbox is empty." }
        let unread = threads.filter { !$0.isRead }.count
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, h:mm a"
        // Newest first, with IDs, so the AI can read or act on a specific email at once.
        let preview = threads.prefix(15).enumerated().map { index, t in
            let gist = t.snippet.replacingOccurrences(of: "\n", with: " ").prefix(140)
            return "\(index + 1). threadID \(t.id.uuidString) | \(t.isRead ? "read" : "UNREAD") | from \(Self.senderName(t)) | \(formatter.string(from: t.latestDate)) | subject: \(t.subject) | preview: \(gist)"
        }.joined(separator: "\n")
        var summary = "Inbox: \(threads.count) threads loaded, \(unread) unread. Newest first:\n\(preview)"
        if !spamThreads.isEmpty {
            let spam = spamThreads.enumerated().map { index, t in
                "\(index + 1). threadID \(t.id.uuidString) | from \(Self.senderName(t)) | subject: \(t.subject)"
            }.joined(separator: "\n")
            summary += "\n\nSPAM FOLDER (already read aloud to the user, same numbering):\n\(spam)"
        }
        return summary
    }

    // Build the spoken string for reading an email according to user preferences
    private func emailReadParts(thread: EmailThread, msg: EmailMessage, prefs: VoicePreferences) -> String {
        let sender  = thread.participants.first?.display ?? "Unknown sender"
        let subject = thread.subject
        let date    = msg.date.formatted(date: .abbreviated, time: .shortened)
        let body    = msg.bodyPlain.isEmpty ? "(No body)" : String(msg.bodyPlain.prefix(1500))

        switch prefs.emailReadOrder {
        case .senderSubjectDateBody:
            return buildEmailString(prefs: prefs, parts: [
                prefs.readSenderName  ? "From: \(sender)." : nil,
                "Subject: \(subject).",
                prefs.readDate        ? "Received: \(date)." : nil,
                body
            ])
        case .subjectSenderDateBody:
            return buildEmailString(prefs: prefs, parts: [
                "Subject: \(subject).",
                prefs.readSenderName  ? "From: \(sender)." : nil,
                prefs.readDate        ? "Received: \(date)." : nil,
                body
            ])
        case .subjectDateSenderBody:
            return buildEmailString(prefs: prefs, parts: [
                "Subject: \(subject).",
                prefs.readDate        ? "Received: \(date)." : nil,
                prefs.readSenderName  ? "From: \(sender)." : nil,
                body
            ])
        case .bodyOnly:
            return body
        case .summaryOnly:
            // Should have been handled by the caller — fall back to body
            return body
        }
    }

    private func buildEmailString(prefs: VoicePreferences, parts: [String?]) -> String {
        parts.compactMap { $0 }.joined(separator: " ")
    }

    private func responseTextWithoutJSON(_ text: String) -> String {
        guard let start = text.range(of: "{"),
              let end   = text.range(of: "}", options: .backwards),
              start.lowerBound < end.upperBound
        else { return text }
        var result = text
        result.removeSubrange(start.lowerBound..<end.upperBound)
        // Drop any code-fence markers left around the removed action block.
        result = result.replacingOccurrences(of: "```json", with: "")
                       .replacingOccurrences(of: "```", with: "")
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
