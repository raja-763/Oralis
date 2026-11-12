import SwiftUI

/// Lumin-style full-screen "call" overlay for hands-free conversation.
/// Shown as a sheet over the main window whenever conversation mode is active.
struct CallView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top bar ──────────────────────────────────────────
                callHeader

                Spacer()

                // ── Main state display ───────────────────────────────
                VStack(spacing: 28) {
                    oralisAvatar
                    statusLabel
                }

                Spacer()

                // ── Last exchange ────────────────────────────────────
                lastExchange
                    .padding(.bottom, 24)

                // ── End call button ──────────────────────────────────
                endCallButton
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Oralis call in progress")
    }

    // MARK: - Header

    private var callHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Oralis")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                if let acc = appState.selectedAccount {
                    Text(acc.emailAddress)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            callTimer
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var callTimer: some View {
        CallTimerView()
            .foregroundStyle(.white.opacity(0.7))
    }

    // MARK: - Avatar / Waveform

    private var oralisAvatar: some View {
        ZStack {
            // Pulsing rings when listening or speaking
            if appState.isAgentListening {
                ForEach(0..<3, id: \.self) { i in
                    PulseRing(delay: Double(i) * 0.3, color: .red)
                }
            } else if appState.speech.isSpeaking {
                ForEach(0..<3, id: \.self) { i in
                    PulseRing(delay: Double(i) * 0.3, color: .blue)
                }
            }

            // Icon
            Circle()
                .fill(
                    appState.isAgentListening ? Color.red.opacity(0.9) :
                    appState.speech.isSpeaking ? Color.blue.opacity(0.9) :
                    Color.white.opacity(0.15)
                )
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: appState.isAgentListening ? "waveform" :
                          appState.speech.isSpeaking ? "speaker.wave.3.fill" :
                          appState.isProcessingResponse ? "ellipsis" :
                          "waveform.circle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.white)
                        .symbolEffect(
                            .variableColor.iterative,
                            isActive: appState.isAgentListening || appState.speech.isSpeaking
                        )
                )
                .animation(.spring(response: 0.4), value: appState.isAgentListening)
                .animation(.spring(response: 0.4), value: appState.speech.isSpeaking)
        }
        .frame(width: 160, height: 160)
        .accessibilityHidden(true)
    }

    // MARK: - Status label

    private var statusLabel: some View {
        Group {
            if appState.isAgentListening {
                Text("Listening…")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.red)
            } else if appState.isProcessingResponse {
                Text("Thinking…")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            } else if appState.speech.isSpeaking {
                Text("Speaking…")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.blue)
            } else {
                Text("Speak anytime")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isAgentListening)
        .animation(.easeInOut(duration: 0.2), value: appState.speech.isSpeaking)
        .accessibilityLabel(
            appState.isAgentListening ? "Listening" :
            appState.isProcessingResponse ? "Thinking" :
            appState.speech.isSpeaking ? "Speaking" :
            "Ready — speak anytime"
        )
    }

    // MARK: - Last exchange

    private var lastExchange: some View {
        VStack(spacing: 10) {
            if let lastUser = appState.agentMessages.last(where: { $0.role == .user }) {
                HStack {
                    Spacer(minLength: 60)
                    Text(lastUser.content)
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.15))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("You said: \(lastUser.content)")
                }
            }
            if let lastOralis = appState.agentMessages.last(where: { $0.role == .assistant }) {
                HStack {
                    Text(lastOralis.content)
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.accentColor.opacity(0.25))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Oralis said: \(lastOralis.content)")
                    Spacer(minLength: 60)
                }
            }
        }
    }

    // MARK: - End call

    private var endCallButton: some View {
        Button {
            appState.stopConversationMode()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 68, height: 68)
                    .shadow(color: .red.opacity(0.5), radius: 12)
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End conversation")
    }
}

// MARK: - Pulse ring animation

private struct PulseRing: View {
    let delay: Double
    let color: Color
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.5

    var body: some View {
        Circle()
            .stroke(color.opacity(opacity), lineWidth: 1.5)
            .frame(width: 100, height: 100)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 1.4)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    scale = 2.2
                    opacity = 0
                }
            }
    }
}

// MARK: - Call timer

private struct CallTimerView: View {
    @State private var elapsed: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatted)
            .font(.caption.monospacedDigit())
            .onReceive(timer) { _ in elapsed += 1 }
            .accessibilityLabel("Call duration \(formatted)")
    }

    private var formatted: String {
        let m = elapsed / 60
        let s = elapsed % 60
        return String(format: "%d:%02d", m, s)
    }
}
