import SwiftUI

/// Full-screen voice interface — the main screen of Oralis.
/// Voice-only: press the mic, speak, Oralis responds.
struct TalkView: View {
    @EnvironmentObject var appState: AppState
    @State private var typedCommand = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversationArea
            Divider()
            typeBar
            micBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
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
                    Text("No account — open Settings to add one")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
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
    }

    // MARK: - Conversation area

    private var conversationArea: some View {
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
                    // Always hidden from VoiceOver navigation. macOS 27 has a SwiftUI bug
                    // where VoiceOver querying dynamic message elements causes
                    // AccessibilityNode.accessibilityLabel() infinite recursion → stack overflow.
                    // All speech is delivered via TTS / VoiceOver announcements instead,
                    // so VO navigation to individual messages is not needed.
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: appState.agentMessages.count) { _, _ in
                if let last = appState.agentMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Talk to Oralis")
                    .font(.title3.weight(.semibold))
                Text("Press the mic and ask anything about your email.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Group {
                    Text("Email")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SuggestionChip("Read my latest emails")
                    SuggestionChip("Summarize my inbox")
                    SuggestionChip("Any emails from my boss?")
                    SuggestionChip("Delete all spam")
                    SuggestionChip("Unsubscribe from promotions")
                }
                Group {
                    Text("Calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    SuggestionChip("What's on my calendar this week?")
                    SuggestionChip("Schedule a meeting tomorrow at 3pm")
                }
                Group {
                    Text("Web")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    SuggestionChip("Go to google.com")
                    SuggestionChip("Read this page")
                }
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Type bar (typed commands, as an alternative to speaking)

    private var typeBar: some View {
        HStack(spacing: 8) {
            TextField("Type a message to Oralis", text: $typedCommand)
                .textFieldStyle(.roundedBorder)
                .onSubmit(sendTypedCommand)
            Button("Send", action: sendTypedCommand)
                .disabled(typedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(.bar)
    }

    private func sendTypedCommand() {
        let text = typedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedCommand = ""
        appState.sendAgentMessage(text)
    }

    // MARK: - Mic bar

    private var micBar: some View {
        VStack(spacing: 10) {
            // Status label + live transcription — hidden from VoiceOver; mic button's
            // accessibilityLabel describes the state, and content is announced via TTS.
            statusLabel
                .accessibilityHidden(true)

            HStack(spacing: 20) {
                // Conversation mode toggle (main action)
                Button {
                    if appState.isConversationMode {
                        appState.stopConversationMode()
                    } else {
                        appState.startConversationMode()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(appState.isConversationMode ? Color.red : Color.accentColor)
                            .frame(width: 72, height: 72)
                            .shadow(
                                color: appState.isConversationMode ? .red.opacity(0.4) : .accentColor.opacity(0.3),
                                radius: appState.isConversationMode ? 16 : 6
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                    .scaleEffect(appState.isAgentListening ? 1.4 : 1.0)
                                    .opacity(appState.isAgentListening ? 0 : 0)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                               value: appState.isAgentListening)
                            )
                        Image(systemName: appState.isConversationMode ? "stop.fill" : "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut("L", modifiers: [.command, .option])
                .accessibilityLabel(appState.isConversationMode
                                    ? "Microphone, on. Press to stop."
                                    : "Microphone. Press to talk to Oralis.")
                .help(appState.isConversationMode ? "End conversation (⌘⌥L)" : "Start conversation (⌘⌥L)")
                .scaleEffect(appState.isAgentListening ? 1.08 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.5), value: appState.isAgentListening)
            }

            Text(appState.isConversationMode
                 ? "Say \"stop\" to end"
                 : "Option+Space to start from anywhere")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if appState.isAgentListening {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                        .accessibilityHidden(true)
                    Text("Listening…")
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                }
                .font(.subheadline)
                if !appState.speech.transcribedText.isEmpty {
                    Text(appState.speech.transcribedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 22)
        } else if appState.speech.isSpeaking {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .symbolEffect(.variableColor.iterative)
                    .accessibilityHidden(true)
                Text("Oralis is speaking…")
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
            }
            .font(.subheadline)
            .frame(minHeight: 22)
        } else if appState.isConversationMode {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Conversation active — speak anytime")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(height: 22)
        } else {
            Text(appState.agentMessages.isEmpty ? "Tap to start a conversation" : "Tap to continue")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .frame(height: 22)
        }
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
                .accessibilityLabel(isUser ? "You said: \(message.content)" : "Oralis: \(message.content)")

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
    }
}
