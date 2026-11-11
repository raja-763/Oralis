import SwiftUI

/// Full-screen voice interface — the main screen of Oralis.
/// Voice-only: press the mic, speak, Oralis responds.
struct TalkView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversationArea
            Divider()
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
        .accessibilityElement(children: .contain)
    }

    // MARK: - Mic bar (voice only — no text input)

    private var micBar: some View {
        VStack(spacing: 10) {
            // Status label
            Group {
                if appState.isAgentListening {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative)
                            .accessibilityHidden(true)
                        Text("Listening…")
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text(appState.agentMessages.isEmpty ? "Tap the mic to speak" : "Tap the mic to respond")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .frame(height: 22)

            // Big mic button
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
                        .frame(width: 72, height: 72)
                        .shadow(
                            color: appState.isAgentListening ? .red.opacity(0.4) : .accentColor.opacity(0.3),
                            radius: appState.isAgentListening ? 16 : 6
                        )
                    Image(systemName: appState.isAgentListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("L", modifiers: [.command, .option])
            .accessibilityLabel(appState.isAgentListening
                                ? "Stop listening — Oralis heard you. Command Option L."
                                : "Start listening. Command Option L.")
            .help(appState.isAgentListening ? "Stop (⌘⌥L)" : "Listen (⌘⌥L)")
            .scaleEffect(appState.isAgentListening ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: appState.isAgentListening)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(.bar)
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
        .accessibilityLabel("Suggested command: \(text)")
    }
}
