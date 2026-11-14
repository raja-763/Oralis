import AppKit
import AVFoundation
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
    private var searchResults: [EmailThread] = []
    private var isLoadingInbox = false

    /// Sends an email and says honestly whether it went.
    private func sendEmail(_ draft: DraftMessage, via account: EmailAccount, success: String) async {
        do {
            try await EmailServiceFactory.service(for: account).sendMessage(draft)
            oralisLog("email: sent")
            SoundEffects.sent()
            readAloud(success)
        } catch {
            oralisLog("email: send failed: \(String(describing: error).prefix(200))")
            readAloud("The email was not sent. \(error.localizedDescription)")
        }
    }

    /// Accepts an email address or a contact's name.
    private func emailAddress(for to: String) async -> EmailAddress? {
        let trimmed = to.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") { return EmailAddress(name: "", address: trimmed) }
        do {
            let found = try await ContactLookup.email(for: trimmed)
            return EmailAddress(name: found.name, address: found.address)
        } catch {
            readAloud(error.localizedDescription)
            return nil
        }
    }

    /// Finds an email the AI refers to, whether it came from the inbox, spam or a search.
    private func knownThread(_ id: String) -> EmailThread? {
        (threads + spamThreads + searchResults).first { $0.id.uuidString == id }
    }

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
                guard let self, conversing else { return }
                if speaking {
                    guard SpeechService.talkOverEnabled else { return }
                    // Keep the mic open while Oralis talks so the user can talk over it.
                    if !listening, !self.bargeInUnavailable { self.startListening(bargeIn: true) }
                } else if listening && self.speech.bargeInPending {
                    // Oralis finished without being interrupted: restart as a normal turn.
                    self.speech.stopListening()
                } else if !listening && !processing {
                    self.startListening()
                }
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
            // Show the last-seen inbox instantly; the fresh copy replaces it moments later.
            if let cached = Self.readInboxCache(for: first), !cached.isEmpty {
                if first.provider == .gmail { GmailService.register(cached) }
                threads = cached
                oralisLog("inbox: \(cached.count) threads restored from cache")
            }
            inboxTask = Task { await refreshInbox(for: first) }
        }
    }

    private var inboxTask: Task<Void, Never>?

    /// Waits (up to `seconds`) for a load that is already running, so a request made
    /// right after launch is answered with the real inbox instead of "still loading".
    private func waitForInbox(seconds: Double = 20) async {
        let deadline = Date().addingTimeInterval(seconds)
        while isLoadingInbox && threads.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private static func inboxCacheURL(for account: EmailAccount) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Oralis", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("inbox-\(account.id.uuidString).json")
    }

    private static func readInboxCache(for account: EmailAccount) -> [EmailThread]? {
        guard let url = inboxCacheURL(for: account), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([EmailThread].self, from: data)
    }

    private func writeInboxCache(_ threads: [EmailThread], for account: EmailAccount) {
        guard let url = Self.inboxCacheURL(for: account) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(threads) { try? data.write(to: url, options: .atomic) }
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
            writeInboxCache(fetched, for: account)
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
            searchResults.removeAll { selectedThreadIDs.contains($0.id) }
            if let open = selectedThread, ids.contains(open.id) { selectedThread = nil }
            selectedThreadIDs.removeAll()
            SoundEffects.deleted()
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
            guard !ids.isEmpty else { announce("I couldn't tell which email you meant."); return }
            try await service.archiveThreads(ids: ids)
            threads.removeAll { selectedThreadIDs.contains($0.id) }
            searchResults.removeAll { selectedThreadIDs.contains($0.id) }
            if let open = selectedThread, ids.contains(open.id) { selectedThread = nil }
            selectedThreadIDs.removeAll()
            announce("Archived \(ids.count) emails.")
        } catch {
            announce("Archive failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Voice + Agent (Talk screen)

    /// Set if the interruption listener could not start, so it is not retried in a loop.
    private var bargeInUnavailable = false
    private var lastBargeInStart = Date.distantPast
    /// Bumped whenever the user talks over Oralis; actions queued before that are dropped.
    private var interruptGeneration = 0

    func startListening(bargeIn: Bool = false) {
        if bargeIn {
            guard Date().timeIntervalSince(lastBargeInStart) > 1.0 else { return }
            lastBargeInStart = Date()
        }
        speech.onBargeIn = { [weak self] heard in
            // Only an explicit "stop / wait / cancel / don't" cancels what Oralis was about to do;
            // a new request alone leaves the earlier steps to finish.
            let words = heard.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
            let cancel: Set<String> = ["stop", "wait", "cancel", "don't", "dont", "no", "nevermind", "undo", "hold"]
            if words.contains(where: cancel.contains) || heard.lowercased().contains("never mind") {
                self?.interruptGeneration += 1
            }
        }
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
                if bargeIn { bargeInUnavailable = true; return }
                readAloud("Microphone access is blocked. Go to System Settings, Privacy and Security, Microphone, and enable Oralis.")
                return
            }
            do {
                try await speech.startListening(locale: locale, bargeIn: bargeIn)
            } catch {
                isAgentListening = false
                if bargeIn {
                    oralisLog("speech: interruption listener failed: \(error.localizedDescription)")
                    bargeInUnavailable = true
                    return
                }
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
        // Only a whole utterance that is nothing but a goodbye ends the conversation.
        // Anything longer ("stop reading and delete it") goes to the AI as a request.
        let bare = lower.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        let stopWords = ["stop listening", "stop", "goodbye", "bye", "that's all", "thats all",
                         "exit", "quit", "oralis stop", "done", "i'm done", "im done"]
        if stopWords.contains(bare) {
            if isConversationMode {
                stopConversationMode()
            } else {
                speech.stopSpeaking()
            }
            return
        }

        // "Heard you" tone — confirms STT captured the request
        NSSound(named: .init("Tink"))?.play()

        agentMessages.append(AgentMessage(role: .user, content: trimmed))


        let prefs = speech.preferences
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
            await waitForInbox()
            let context = buildContext()
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
                let generation = interruptGeneration
                readAloud(spoken)
                // Carry out each requested action in order, letting Oralis finish
                // speaking between them so one result does not cut off the last.
                for action in response.actions {
                    await waitForSpeechToFinish()
                    // The user talked over Oralis: drop what was about to happen.
                    guard generation == interruptGeneration else {
                        oralisLog("command: remaining actions dropped after interruption")
                        break
                    }
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
            if let thread = knownThread(threadID),
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
            if let thread = knownThread(threadID),
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
            guard let account = selectedAccount else { return }
            guard let thread = knownThread(threadID), let msg = thread.messages.last ?? thread.messages.first else {
                readAloud("I couldn't find the email you want to reply to.")
                return
            }
            let draft = DraftMessage(
                to: [msg.from],
                subject: thread.subject.hasPrefix("Re:") ? thread.subject : "Re: \(thread.subject)",
                body: body,
                replyToMessageID: msg.remoteID
            )
            await sendEmail(draft, via: account, success: "Reply sent to \(Self.senderName(thread)).")

        case .forward(let threadID, let toAddress, let body):
            guard let account = selectedAccount else { return }
            guard let thread = knownThread(threadID), let msg = thread.messages.last ?? thread.messages.first else {
                readAloud("I couldn't find the email you want to forward.")
                return
            }
            guard let address = await emailAddress(for: toAddress) else { return }
            let draft = DraftMessage(
                to: [address],
                subject: thread.subject.hasPrefix("Fwd:") ? thread.subject : "Fwd: \(thread.subject)",
                body: body,
                forwardOfMessageID: msg.remoteID
            )
            await sendEmail(draft, via: account, success: "Forwarded to \(address.name.isEmpty ? address.address : address.name).")

        case .draft(let to, let subject, let body):
            guard let account = selectedAccount else { return }
            guard let address = await emailAddress(for: to) else { return }
            let draft = DraftMessage(to: [address], subject: subject, body: body)
            await sendEmail(draft, via: account, success: "Email sent to \(address.name.isEmpty ? address.address : address.name).")

        case .markRead(let ids, let read):
            guard let account = selectedAccount else { return }
            let uuids = ids.compactMap { UUID(uuidString: $0) }
            guard !uuids.isEmpty else { readAloud("I couldn't tell which email you meant."); return }
            do {
                try await EmailServiceFactory.service(for: account).markRead(ids: uuids, read: read)
                for index in threads.indices where uuids.contains(threads[index].id) { threads[index].isRead = read }
                readAloud(read ? "Marked as read." : "Marked as unread.")
            } catch {
                readAloud("I couldn't change that. \(error.localizedDescription)")
            }

        case .star(let ids, let starred):
            guard let account = selectedAccount else { return }
            let uuids = ids.compactMap { UUID(uuidString: $0) }
            guard !uuids.isEmpty else { readAloud("I couldn't tell which email you meant."); return }
            do {
                try await EmailServiceFactory.service(for: account).starThreads(ids: uuids, starred: starred)
                readAloud(starred ? "Starred." : "Star removed.")
            } catch {
                readAloud("I couldn't change that. \(error.localizedDescription)")
            }

        case .search(let query):
            guard let account = selectedAccount else { return }
            let service = EmailServiceFactory.service(for: account)
            // Results are kept apart from the inbox so a search never empties it.
            do {
                searchResults = try await service.searchThreads(query: query)
                let spoken: String
                if searchResults.isEmpty {
                    spoken = "I found nothing for that search."
                } else {
                    let lines = searchResults.prefix(5).enumerated().map { index, t in
                        "\(index + 1), from \(Self.senderName(t)): \(t.subject)."
                    }.joined(separator: " ")
                    spoken = "I found \(searchResults.count). \(lines)"
                }
                agentMessages.append(AgentMessage(role: .assistant, content: spoken))
                readAloud(spoken)
            } catch {
                oralisLog("search failed: \(String(describing: error).prefix(200))")
                readAloud("The search didn't work. Please try again.")
            }

        case .unsubscribe(let threadID):
            guard let account = selectedAccount,
                  let thread = knownThread(threadID),
                  let msg = thread.messages.first
            else { return }
            let service = EmailServiceFactory.service(for: account)
            do {
                try await service.unsubscribe(from: msg)
                readAloud("Unsubscribed.")
            } catch {
                oralisLog("unsubscribe failed: \(String(describing: error).prefix(200))")
                readAloud("I couldn't unsubscribe from that sender. \(error.localizedDescription)")
            }

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
                searchResults.removeAll { uuids.contains($0.id) }
                readAloud(uuids.count == 1 ? "Moved it to spam." : "Moved \(uuids.count) emails to spam.")
            } catch {
                oralisLog("spam: mark failed: \(String(describing: error).prefix(200))")
                readAloud("I couldn't move that to spam. \(error.localizedDescription)")
            }

        case .moveToInbox(let ids):
            guard let account = selectedAccount else { return }
            let uuids = ids.compactMap { UUID(uuidString: $0) }
            guard !uuids.isEmpty else { readAloud("I couldn't tell which email you meant."); return }
            do {
                try await EmailServiceFactory.service(for: account).moveToInbox(ids: uuids)
                spamThreads.removeAll { uuids.contains($0.id) }
                searchResults.removeAll { uuids.contains($0.id) }
                oralisLog("moveToInbox: moved \(uuids.count)")
                readAloud(uuids.count == 1 ? "Moved it back to your inbox." : "Moved \(uuids.count) emails back to your inbox.")
                await refreshInbox(for: account)
            } catch {
                oralisLog("moveToInbox failed: \(String(describing: error).prefix(200))")
                readAloud("I couldn't move that to your inbox. \(error.localizedDescription)")
            }

        case .deleteSpam:
            guard let account = selectedAccount else { return }
            let service = EmailServiceFactory.service(for: account)
            do {
                let spam = try await service.fetchSpam(limit: 100)
                guard !spam.isEmpty else { readAloud("Your spam folder is already empty."); return }
                try await service.deleteThreads(ids: spam.map(\.id))
                spamThreads = []
                SoundEffects.deleted()
                readAloud("Moved \(spam.count) spam emails to the trash.")
            } catch {
                oralisLog("spam: empty failed: \(String(describing: error).prefix(200))")
                readAloud("I couldn't empty the spam folder. \(error.localizedDescription)")
            }

        // ── Voice ────────────────────────────────────────────────────────
        case .setVoice(let name, let gender, let language, let speed, let pitch):
            applyVoiceChange(name: name, gender: gender, language: language, speed: speed, pitch: pitch)

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
            guard let thread = knownThread(threadID),
                  let invite = thread.messages.first?.calendarInvite
            else { return }
            await requestCalendarAccessWithGuidance()
            do {
                try await CalendarService.shared.addInvite(invite)
                readAloud("Invite accepted and added to your calendar.")
            } catch {
                readAloud("I couldn't add that invite to your calendar. \(error.localizedDescription)")
            }

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

    // MARK: - Voice changes

    private static func genderWord(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.gender {
        case .male:   return "male"
        case .female: return "female"
        default:      return "neutral"
        }
    }

    /// Installed voices in the user's language, listed for the AI so it can pick one by name.
    private func voiceListForAI() -> String {
        let prefs = speech.preferences
        let prefix = prefs.language.split(separator: "-").first.map(String.init) ?? "en"
        let current = prefs.voiceIdentifier
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality.rawValue : $0.name < $1.name }
            .prefix(40)
        return voices.map { v in
            "\(v.name) | \(Self.genderWord(v)) | \(v.language)\(v.identifier == current ? " | CURRENT" : "")"
        }.joined(separator: "\n")
    }

    private func applyVoiceChange(name: String, gender: String, language: String, speed: String, pitch: String) {
        var prefs = speech.preferences
        var voiceChanged = false

        let wantsVoiceChange = !name.isEmpty || !gender.isEmpty || !language.isEmpty
            || (speed.isEmpty && pitch.isEmpty)   // "change your voice" alone
        if wantsVoiceChange {
            let defaultPrefix = prefs.language.split(separator: "-").first.map(String.init) ?? "en"
            var pool = AVSpeechSynthesisVoice.speechVoices()
            if !name.isEmpty {
                let wanted = name.lowercased()
                pool = pool.filter { $0.name.lowercased().contains(wanted) }
            } else {
                if !language.isEmpty {
                    let lang = language.lowercased()
                    let exact = pool.filter { $0.language.lowercased() == lang }
                    pool = exact.isEmpty ? pool.filter { $0.language.lowercased().hasPrefix(lang.prefix(2)) } : exact
                } else {
                    pool = pool.filter { $0.language.hasPrefix(defaultPrefix) }
                }
                switch gender.lowercased() {
                case "male", "man":     pool = pool.filter { $0.gender == .male }
                case "female", "woman": pool = pool.filter { $0.gender == .female }
                default: break
                }
            }
            // Never "change" to the voice already in use; prefer the best quality available.
            let candidates = pool.filter { $0.identifier != prefs.voiceIdentifier }
            let pick = (candidates.isEmpty ? pool : candidates)
                .sorted { $0.quality.rawValue > $1.quality.rawValue }.first
            if let pick {
                prefs.voiceIdentifier = pick.identifier
                prefs.useElevenLabs = false   // an explicit voice request means the system voice
                voiceChanged = true
            } else {
                readAloud("I couldn't find an installed voice like that. You can add more voices in System Settings, under Accessibility, Spoken Content.")
                return
            }
        }

        switch speed.lowercased() {
        case "slower", "slow": prefs.rate = max(0.1, prefs.rate - 0.07)
        case "faster", "fast": prefs.rate = min(0.65, prefs.rate + 0.07)
        case "normal":         prefs.rate = AVSpeechUtteranceDefaultSpeechRate
        default: break
        }
        switch pitch.lowercased() {
        case "higher", "high": prefs.pitch = min(2.0, prefs.pitch + 0.2)
        case "lower", "low", "deeper": prefs.pitch = max(0.5, prefs.pitch - 0.2)
        case "normal":         prefs.pitch = 1.0
        default: break
        }

        speech.preferences = prefs
        VoicePreferencesStore.shared.current = prefs
        oralisLog("voice: changed (voice \(voiceChanged), rate \(prefs.rate), pitch \(prefs.pitch))")

        // Speak the confirmation in the new voice so the user hears the result at once.
        let current = AVSpeechSynthesisVoice(identifier: prefs.voiceIdentifier)?.name
        if voiceChanged, let current {
            readAloud("Okay, this is \(current). How does this sound?")
        } else {
            readAloud("Okay, how does this sound?")
        }
    }

    // MARK: - Helpers

    private func buildContext() -> EmailAgentContext {
        EmailAgentContext(
            inboxSummary: inboxSummary(),
            selectedThread: selectedThread,
            webPageURL: browser.currentURL,
            webPageContent: browser.pageText.isEmpty ? nil : String(browser.pageText.prefix(2000)),
            calendarSummary: calendarSummary.isEmpty ? nil : calendarSummary,
            availableVoices: voiceListForAI()
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
        if !searchResults.isEmpty {
            let found = searchResults.enumerated().map { index, t in
                "\(index + 1). threadID \(t.id.uuidString) | from \(Self.senderName(t)) | subject: \(t.subject)"
            }.joined(separator: "\n")
            summary += "\n\nSEARCH RESULTS (already read aloud to the user, same numbering):\n\(found)"
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
        var result = text
        for block in AIAgentService.jsonBlocks(in: text).reversed() {
            result.removeSubrange(block)
        }
        // Drop any code-fence markers left around the removed action blocks.
        result = result.replacingOccurrences(of: "```json", with: "")
                       .replacingOccurrences(of: "```", with: "")
        // The model sometimes narrates an action as "[Action: ...]"; that is not for speech.
        result = result.replacingOccurrences(of: "\\[\\s*Actions?\\s*:[^\\]]*\\]", with: "",
                                             options: [.regularExpression, .caseInsensitive])
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Waits until Oralis has stopped speaking (at most 90 seconds).
    private func waitForSpeechToFinish() async {
        var waited = 0
        while speech.isSpeaking && waited < 900 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
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
