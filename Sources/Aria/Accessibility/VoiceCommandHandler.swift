import Foundation

/// Routes spoken commands to app actions.
/// Called by SpeechService when a final transcript is available.
@MainActor
final class VoiceCommandHandler {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func handle(_ transcript: String) async {
        let t = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let state = appState else { return }

        // --- Inbox navigation ---
        if t.contains("read") && (t.contains("email") || t.contains("message")) {
            if let thread = state.selectedThread ?? state.threads.first {
                let body = thread.latestMessage?.bodyPlain ?? ""
                state.speech.speak("Email from \(thread.participants.first?.display ?? "unknown"). Subject: \(thread.subject). \(body)")
            }

        } else if t.contains("next email") || t.contains("next message") {
            selectNext(in: state)

        } else if t.contains("previous email") || t.contains("previous message") {
            selectPrevious(in: state)

        } else if t.contains("open agent") || t.contains("open assistant") {
            state.showAgentPanel = true
            state.announce("AI assistant opened.")

        // --- Batch actions ---
        } else if t.contains("delete") && t.contains("spam") {
            await handleDeleteSpam(state: state)

        } else if t.contains("delete") && t.contains("selected") {
            await state.deleteSelected()

        } else if t.contains("archive") && t.contains("selected") {
            await state.archiveSelected()

        } else if t.contains("select all") {
            state.selectedThreadIDs = Set(state.threads.map(\.id))
            state.announce("Selected all \(state.threads.count) emails.")

        } else if t.contains("clear selection") || t.contains("deselect") {
            state.selectedThreadIDs.removeAll()
            state.announce("Selection cleared.")

        // --- Unsubscribe ---
        } else if t.contains("unsubscribe") {
            if let thread = state.selectedThread,
               let msg = thread.latestMessage,
               msg.hasUnsubscribeOption,
               let acc = state.selectedAccount {
                let svc = EmailServiceFactory.service(for: acc)
                do {
                    try await svc.unsubscribe(from: msg)
                    state.announce("Unsubscribed from \(thread.subject).")
                } catch {
                    state.announce("Unsubscribe failed.")
                }
            } else {
                state.announce("No unsubscribe option in the current email.")
            }

        // --- Reply ---
        } else if t.hasPrefix("reply") {
            state.announce("Opening reply. Please type or dictate your reply.")

        // --- Refresh ---
        } else if t.contains("refresh") || t.contains("check for new mail") {
            if let acc = state.selectedAccount {
                state.announce("Checking for new mail.")
                await state.refreshInbox(for: acc)
            }

        // --- How many ---
        } else if t.contains("how many") && (t.contains("unread") || t.contains("email")) {
            let unread = state.threads.filter { !$0.isRead }.count
            state.announce("You have \(unread) unread email\(unread == 1 ? "" : "s").")

        // --- Read links ---
        } else if t.contains("read links") || t.contains("list links") {
            if let links = state.selectedThread?.latestMessage?.links, !links.isEmpty {
                let titles = links.prefix(5).map { $0.title.isEmpty ? $0.url.host ?? "link" : $0.title }
                state.announce("Links in this email: \(titles.joined(separator: ", "))")
            } else {
                state.announce("No links found in this email.")
            }

        // --- Help ---
        } else if t.contains("what can you do") || t.contains("help") {
            state.announce("You can say: read email, next email, previous email, delete spam, select all, archive selected, unsubscribe, refresh, how many unread, or open assistant.")

        } else {
            // Fall through to AI agent for anything not matched
            state.showAgentPanel = true
        }
    }

    // MARK: - Helpers

    private func selectNext(in state: AppState) {
        guard !state.threads.isEmpty else { return }
        if let current = state.selectedThread,
           let idx = state.threads.firstIndex(where: { $0.id == current.id }),
           idx + 1 < state.threads.count {
            state.selectedThread = state.threads[idx + 1]
            state.announce(state.threads[idx + 1].accessibilityLabel)
        } else {
            state.selectedThread = state.threads[0]
            state.announce(state.threads[0].accessibilityLabel)
        }
    }

    private func selectPrevious(in state: AppState) {
        guard !state.threads.isEmpty else { return }
        if let current = state.selectedThread,
           let idx = state.threads.firstIndex(where: { $0.id == current.id }),
           idx > 0 {
            state.selectedThread = state.threads[idx - 1]
            state.announce(state.threads[idx - 1].accessibilityLabel)
        }
    }

    private func handleDeleteSpam(state: AppState) async {
        guard let acc = state.selectedAccount else { return }
        let svc = EmailServiceFactory.service(for: acc)
        state.announce("Fetching spam emails.")
        do {
            let spam = try await svc.fetchSpam(limit: 200)
            if spam.isEmpty {
                state.announce("No spam emails found.")
                return
            }
            state.announce("Found \(spam.count) spam emails. Deleting now.")
            state.selectedThreadIDs = Set(spam.map(\.id))
            await state.deleteSelected()
        } catch {
            state.announce("Could not fetch spam: \(error.localizedDescription)")
        }
    }
}
