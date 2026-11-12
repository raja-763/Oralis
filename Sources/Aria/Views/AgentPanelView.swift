import SwiftUI

/// Floating AI assistant panel — voice-first, accessible.
/// Docked to the bottom-right corner of the main window.
struct AgentPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    @State private var isThinking = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                Label("Oralis Assistant", systemImage: "waveform.circle.fill")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    appState.showAgentPanel = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close assistant panel")
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.12))

            Divider()

            // Message history
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if appState.agentMessages.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "waveform.circle")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("Say or type something to start.\nTry: \"Read my latest emails\" or \"Delete all spam\".")
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                            .accessibilityLabel("No messages yet. Ask Aria about your email.")
                        }

                        ForEach(appState.agentMessages) { msg in
                            AgentMessageBubble(message: msg)
                                .id(msg.id)
                        }

                        if isThinking {
                            HStack(spacing: 6) {
                                ForEach(0..<3) { i in
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 7, height: 7)
                                        .opacity(0.6)
                                }
                            }
                            .padding(.leading, 12)
                            .accessibilityLabel("Oralis is thinking")
                        }
                    }
                    .padding(12)
                }
                .onChange(of: appState.agentMessages.count) { _, _ in
                    if let last = appState.agentMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                // Voice button
                Button {
                    toggleVoice()
                } label: {
                    Image(systemName: appState.isAgentListening ? "mic.fill" : "mic")
                        .foregroundStyle(appState.isAgentListening ? .red : .accentColor)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.isAgentListening ? "Stop listening" : "Start voice input")
                .keyboardShortcut("L", modifiers: [.command, .option])

                // Text field
                TextField(appState.isAgentListening
                          ? appState.speech.transcribedText.isEmpty ? "Listening…" : appState.speech.transcribedText
                          : "Ask Aria…",
                          text: $inputText)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit { Task { await sendMessage() } }
                    .accessibilityLabel("Type a message or press the microphone button to speak")

                if !inputText.isEmpty || isThinking {
                    Button {
                        Task { await sendMessage() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(isThinking)
                    .accessibilityLabel("Send message")
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 4)
        .onAppear {
            fieldFocused = true
            appState.speech.onFinalResult = { text in
                Task { @MainActor in
                    inputText = text
                    await sendMessage()
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleVoice() {
        if appState.isAgentListening {
            appState.speech.stopListening()
            appState.isAgentListening = false
        } else {
            Task {
                let ok = await appState.speech.requestPermissions()
                guard ok else {
                    appState.announce("Microphone permission denied. Please allow it in System Settings.")
                    return
                }
                try? await appState.speech.startListening(locale: appState.speech.preferences.language)
                appState.isAgentListening = true
            }
        }
    }

    private func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appState.isAgentListening = false
        appState.speech.stopListening()

        let userMsg = AgentMessage(role: .user, content: text)
        appState.agentMessages.append(userMsg)
        isThinking = true

        let context = EmailAgentContext(
            inboxSummary: buildInboxSummary(),
            selectedThread: appState.selectedThread,
            webPageURL: appState.browser.currentURL,
            webPageContent: appState.browser.pageText.isEmpty ? nil : String(appState.browser.pageText.prefix(2000)),
            calendarSummary: appState.calendarSummary.isEmpty ? nil : appState.calendarSummary
        )

        do {
            let response = try await appState.agent.send(
                userMessage: text,
                history: appState.agentMessages.dropLast(),
                context: context
            )
            isThinking = false

            let assistantMsg = AgentMessage(role: .assistant, content: response.text)
            appState.agentMessages.append(assistantMsg)
            appState.speech.speak(response.text)

            // Execute any action the agent returned
            if let action = response.action {
                await executeAction(action)
            }
        } catch {
            isThinking = false
            let errMsg = AgentMessage(role: .assistant,
                                      content: "Sorry, I had a problem: \(error.localizedDescription)")
            appState.agentMessages.append(errMsg)
        }
    }

    private func buildInboxSummary() -> String {
        let total  = appState.threads.count
        let unread = appState.threads.filter { !$0.isRead }.count
        let first3 = appState.threads.prefix(3).map { "- \($0.subject) from \($0.participants.first?.display ?? "")" }.joined(separator: "\n")
        return "Current inbox: \(total) threads, \(unread) unread.\nLatest:\n\(first3)"
    }

    private func executeAction(_ action: AgentAction) async {
        switch action {
        case .delete(let ids):
            appState.selectedThreadIDs = Set(appState.threads.filter { ids.contains($0.remoteThreadID) }.map(\.id))
            await appState.deleteSelected()
        case .archive(let ids):
            appState.selectedThreadIDs = Set(appState.threads.filter { ids.contains($0.remoteThreadID) }.map(\.id))
            await appState.archiveSelected()
        case .search(let query):
            if let acc = appState.selectedAccount {
                let svc = EmailServiceFactory.service(for: acc)
                if let results = try? await svc.searchThreads(query: query) {
                    appState.threads = results
                }
            }
        case .deleteSpam:
            if let acc = appState.selectedAccount {
                let svc = EmailServiceFactory.service(for: acc)
                if let spam = try? await svc.fetchSpam(limit: 200) {
                    appState.selectedThreadIDs = Set(spam.map(\.id))
                    await appState.deleteSelected()
                }
            }
        case .openLink(let url):
            appState.navigationPath.append(url)
        default:
            // All other actions are handled via AppState.sendAgentMessage / execute
            break
        }
    }
}

// MARK: - Message bubble

struct AgentMessageBubble: View {
    let message: AgentMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.content)
                .padding(10)
                .background(message.role == .user ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .accessibilityLabel("\(message.role == .user ? "You" : "Oralis"): \(message.content)")
    }
}
