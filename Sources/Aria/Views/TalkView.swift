import SwiftUI

/// Full-screen voice interface — the main screen of Oralis.
/// Users talk to Oralis here to manage their email entirely by voice.
struct TalkView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Oralis")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    if let acc = appState.selectedAccount {
                        Text(acc.emailAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No account connected")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                // Account switcher if multiple accounts
                if appState.accounts.count > 1 {
                    Menu {
                        ForEach(appState.accounts) { acc in
                            Button(acc.emailAddress) {
                                appState.selectedAccount = acc
                            }
                        }
                    } label: {
                        Image(systemName: "person.2.fill")
                            .accessibilityLabel("Switch account")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)

            Divider()

            // ── Conversation ─────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    if appState.agentMessages.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(appState.agentMessages) { msg in
                                MessageBubble(message: msg)
                            }
                        }
                        .padding(16)
                    }
                }
                .onChange(of: appState.agentMessages.count) { _, _ in
                    if let last = appState.agentMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // ── Input bar ────────────────────────────────────────────
            inputBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Talk to Oralis")
                    .font(.title3.weight(.semibold))
                Text("Press the mic or type a command below.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                SuggestionChip("Read my latest emails")
                SuggestionChip("How many unread do I have?")
                SuggestionChip("Delete all spam")
                SuggestionChip("Unsubscribe from promotions")
                SuggestionChip("Any emails from my boss?")
            }
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Mic button
            Button {
                if appState.isAgentListening {
                    appState.stopListening()
                } else {
                    appState.startListening()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(appState.isAgentListening ? Color.red : Color.accentColor)
                        .frame(width: 44, height: 44)
                    Image(systemName: appState.isAgentListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("L", modifiers: [.command, .option])
            .accessibilityLabel(appState.isAgentListening ? "Stop listening" : "Start listening — shortcut Command Option L")
            .help(appState.isAgentListening ? "Stop (⌘⌥L)" : "Start listening (⌘⌥L)")

            // Transcription / text input
            ZStack(alignment: .leading) {
                if inputText.isEmpty {
                    Text(appState.isAgentListening ? "Listening…" : "Type a command or press the mic")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextField("", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 10)
                    .focused($inputFocused)
                    .accessibilityLabel("Type your command here")
                    .onSubmit { sendText() }
            }
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 22))

            // Send button
            Button(action: sendText) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(inputText.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty && !appState.isAgentListening)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        // Mirror live transcription into the text field
        .onReceive(appState.speech.$transcribedText) { text in
            if appState.isAgentListening && !text.isEmpty {
                inputText = text
            }
        }
        // Send when listening stops with captured text
        .onReceive(appState.speech.$isListening) { listening in
            if !listening && !inputText.isEmpty {
                sendText()
            }
        }
    }

    // MARK: - Actions

    private func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appState.sendAgentMessage(text)
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: AgentMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                Image(systemName: "waveform.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }

            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .textSelection(.enabled)
                .accessibilityLabel(isUser ? "You: \(message.content)" : "Oralis: \(message.content)")

            if isUser {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .id(message.id)
    }
}

// MARK: - Suggestion chip

struct SuggestionChip: View {
    let text: String
    @EnvironmentObject var appState: AppState

    init(_ text: String) { self.text = text }

    var body: some View {
        Button {
            appState.sendAgentMessage(text)
        } label: {
            Text(text)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Suggested command: \(text)")
    }
}
