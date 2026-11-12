import SwiftUI

/// Compact voice interface shown in the floating menu bar panel.
/// Mirrors TalkView but sized for the smaller floating window.
struct FloatingPanelView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // ── Drag handle + account ────────────────────────────────
            panelHeader

            Divider()

            // ── Conversation ─────────────────────────────────────────
            conversationScroll

            Divider()

            // ── Mic button ───────────────────────────────────────────
            micSection
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Oralis")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let acc = appState.selectedAccount {
                    Text(acc.emailAddress)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No account")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Open full window
            Button {
                NSApp.activate(ignoringOtherApps: true)
                for w in NSApp.windows where !(w is FloatingPanel) {
                    w.makeKeyAndOrderFront(nil)
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open full Oralis window")
            .help("Open full window")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Conversation

    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if appState.agentMessages.isEmpty {
                    panelEmptyState
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(appState.agentMessages) { msg in
                            PanelBubble(message: msg)
                        }
                    }
                    .padding(12)
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: appState.agentMessages.count) { _, _ in
                if let last = appState.agentMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var panelEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Press the mic and talk")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                PanelChip("Read my latest emails")
                PanelChip("How many unread?")
                PanelChip("Delete all spam")
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Mic

    private var micSection: some View {
        VStack(spacing: 6) {
            // Status label
            Group {
                if appState.isAgentListening {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative)
                            .accessibilityHidden(true)
                        Text("Listening…")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                    }
                } else if appState.speech.isSpeaking {
                    HStack(spacing: 5) {
                        Image(systemName: "speaker.wave.2")
                            .symbolEffect(.variableColor.iterative)
                            .accessibilityHidden(true)
                        Text("Speaking…")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                } else if appState.isConversationMode {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Active — speak anytime")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("⌥Space from anywhere")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 18)

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
                        .frame(width: 56, height: 56)
                        .shadow(color: appState.isConversationMode
                                ? .red.opacity(0.4) : .accentColor.opacity(0.3),
                                radius: appState.isConversationMode ? 12 : 5)
                    Image(systemName: appState.isConversationMode ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(appState.isAgentListening ? 1.08 : 1.0)
            .animation(.spring(response: 0.3), value: appState.isAgentListening)
            .accessibilityLabel(appState.isConversationMode ? "End conversation" : "Start conversation with Oralis")

            Text(appState.isConversationMode ? "Say \"stop\" to end" : "Tap to start")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

// MARK: - Panel bubble (compact)

struct PanelBubble: View {
    let message: AgentMessage
    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 32) }
            Text(message.content)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isUser ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(isUser ? "You: \(message.content)" : "Oralis: \(message.content)")
            if !isUser { Spacer(minLength: 32) }
        }
        .id(message.id)
    }
}

// MARK: - Panel suggestion chip

struct PanelChip: View {
    let text: String
    @EnvironmentObject var appState: AppState
    init(_ text: String) { self.text = text }
    var body: some View {
        Button { appState.sendAgentMessage(text) } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
    }
}
