import AVFoundation
import SwiftUI

// MARK: - Onboarding coordinator

/// Seven-step accessible onboarding flow.
/// Each step is announced via VoiceOver and read aloud automatically
/// so a user who opens Aria for the first time — without sighted help —
/// can complete setup entirely by voice.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var step: OnboardingStep = .welcome

    var body: some View {
        ZStack {
            // Animated gradient background (accessible: purely decorative)
            LinearGradient(
                colors: [Color.accentColor.opacity(0.15), Color.purple.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                // Progress bar
                OnboardingProgressBar(current: step.index, total: OnboardingStep.allCases.count)
                    .padding(.horizontal, 48)
                    .padding(.top, 32)

                // Step content
                Group {
                    switch step {
                    case .welcome:      WelcomeStep(advance: advance)
                    case .voiceSetup:   VoiceSetupStep(advance: advance)
                    case .addAccount:   AddAccountStep(advance: advance)
                    case .mailImport:   MailImportStep(advance: advance)
                    case .agentSetup:   AgentSetupStep(advance: advance)
                    case .featureTour:  FeatureTourStep(advance: advance)
                    case .ready:        ReadyStep(finish: finish)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(step)
                .padding(48)
            }
        }
        .frame(minWidth: 680, minHeight: 540)
        .onAppear {
            // Auto-read the first step
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appState.speech.speak(OnboardingStep.welcome.spokenIntro)
            }
        }
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.3)) {
            step = step.next ?? step
        }
        // Read the new step aloud
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let next = step.spokenIntro as String?, !next.isEmpty {
                appState.speech.speak(next)
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "aria.onboardingComplete")
        appState.showOnboarding = false
    }
}

// MARK: - Steps enum

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, voiceSetup, addAccount, mailImport, agentSetup, featureTour, ready

    var id: Int { rawValue }
    var index: Int { rawValue }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var spokenIntro: String {
        switch self {
        case .welcome:
            return "Welcome to Aria, your voice-first email assistant. I will guide you through setup. Everything can be done by voice or keyboard."
        case .voiceSetup:
            return "Let's choose a voice for me. Pick the one that sounds best to you, then adjust the speed and pitch."
        case .addAccount:
            return "Now let's connect your email. You can add Gmail, Outlook, iCloud, Yahoo, or any IMAP account."
        case .mailImport:
            return "I found some accounts already set up in macOS Mail. Would you like to import them?"
        case .agentSetup:
            return "To use the AI assistant, enter your Anthropic API key. This is stored only on your Mac in the secure Keychain."
        case .featureTour:
            return "Here is a quick tour of what Aria can do."
        case .ready:
            return "You are all set! Press Get Started to open your inbox."
        }
    }
}

// MARK: - Progress bar

struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: 4)
                    .animation(.easeInOut, value: current)
            }
        }
        .accessibilityLabel("Step \(current + 1) of \(total)")
        .accessibilityValue("\(Int(Double(current + 1) / Double(total) * 100))% complete")
    }
}

// MARK: - Step shell (shared layout)

struct OnboardingStepShell<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let primaryLabel: String
    let primaryAction: () -> Void
    var skipLabel: String? = nil
    var skipAction: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 28) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            // Heading
            VStack(spacing: 8) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Step-specific content
            content()
                .frame(maxWidth: 500)

            // Buttons
            VStack(spacing: 10) {
                Button(primaryLabel, action: primaryAction)
                    .buttonStyle(OnboardingPrimaryButton())
                    .keyboardShortcut(.return, modifiers: [])

                if let skipLabel, let skipAction {
                    Button(skipLabel, action: skipAction)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(skipLabel)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OnboardingPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 40)
            .padding(.vertical, 14)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Step 1: Welcome

struct WelcomeStep: View {
    let advance: () -> Void
    @EnvironmentObject var appState: AppState

    var body: some View {
        OnboardingStepShell(
            icon: "waveform.circle.fill",
            title: "Welcome to Aria",
            subtitle: "A voice-first email assistant, built for screen reader users.",
            primaryLabel: "Get Started",
            primaryAction: advance
        ) {
            VStack(alignment: .leading, spacing: 14) {
                FeaturePill(icon: "mic.fill",          text: "Control everything by voice")
                FeaturePill(icon: "envelope.fill",     text: "Read, reply, and manage email hands-free")
                FeaturePill(icon: "trash.fill",        text: "Delete 100 spam emails in one command")
                FeaturePill(icon: "bell.slash.fill",   text: "Unsubscribe from lists by voice")
                FeaturePill(icon: "calendar.badge.checkmark", text: "Accept or decline meeting invites by voice")
                FeaturePill(icon: "accessibility",     text: "Accessibility-first, VoiceOver-native")
            }
        }
        .onAppear {
            // Post VoiceOver announcement
            NSAccessibility.post(element: NSApp as Any,
                                 notification: .announcementRequested,
                                 userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: OnboardingStep.welcome.spokenIntro])
        }
    }
}

struct FeaturePill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
        }
        .accessibilityLabel(text)
    }
}

// MARK: - Step 2: Voice setup

struct VoiceSetupStep: View {
    let advance: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var voices = AriaVoice.allEnglishVoices()
    @State private var selectedID = VoicePreferencesStore.shared.current.voiceIdentifier
    @State private var rate: Float = VoicePreferencesStore.shared.current.rate
    @State private var pitch: Float = VoicePreferencesStore.shared.current.pitch

    var premiumVoices: [AriaVoice] { voices.filter { $0.quality == .premium } }
    var otherVoices:   [AriaVoice] { voices.filter { $0.quality != .premium } }

    var body: some View {
        OnboardingStepShell(
            icon: "speaker.wave.3.fill",
            title: "Choose Your Voice",
            subtitle: "Pick the voice that feels right. You can change it later in Settings.",
            primaryLabel: "Sounds Good — Continue",
            primaryAction: { saveAndAdvance() }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Premium voices carousel
                if !premiumVoices.isEmpty {
                    Text("Premium voices")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(premiumVoices) { voice in
                                VoiceChip(voice: voice,
                                          isSelected: voice.id == selectedID,
                                          onTap: { select(voice) },
                                          onPreview: { preview(voice) })
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .accessibilityLabel("Premium voices — swipe to browse, tap to select and preview")
                }

                // Other voices
                if !otherVoices.isEmpty {
                    Text("More voices")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(otherVoices.prefix(12)) { voice in
                                VoiceChip(voice: voice,
                                          isSelected: voice.id == selectedID,
                                          onTap: { select(voice) },
                                          onPreview: { preview(voice) })
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                Divider()

                // Speed slider
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reading speed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("Slow").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $rate,
                               in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
                            .accessibilityLabel("Reading speed")
                            .onChange(of: rate) { _, _ in previewCurrentSettings() }
                        Text("Fast").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Button("Download more voices in System Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.callout)
                .accessibilityLabel("Open System Settings to download additional high-quality voices")
            }
        }
    }

    private func select(_ voice: AriaVoice) {
        selectedID = voice.id
        preview(voice)
    }

    private func preview(_ voice: AriaVoice) {
        var p = VoicePreferencesStore.shared.current
        p.voiceIdentifier = voice.id
        p.rate = rate
        appState.speech.speak("Hi, I'm \(voice.name). I'll be reading your emails for you.", prefs: p)
    }

    private func previewCurrentSettings() {
        var p = VoicePreferencesStore.shared.current
        p.voiceIdentifier = selectedID
        p.rate = rate
        appState.speech.speak("Reading speed adjusted.", prefs: p)
    }

    private func saveAndAdvance() {
        var prefs = VoicePreferencesStore.shared.current
        prefs.voiceIdentifier = selectedID
        prefs.rate = rate
        prefs.pitch = pitch
        VoicePreferencesStore.shared.current = prefs
        appState.speech.preferences = prefs
        advance()
    }
}

struct VoiceChip: View {
    let voice: AriaVoice
    let isSelected: Bool
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: "person.wave.2.fill")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .accentColor)
                    .accessibilityHidden(true)
                Text(voice.name)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(voice.qualityLabel)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(voice.name), \(voice.qualityLabel). \(isSelected ? "Selected." : "Tap to select and preview.")")
        .contextMenu {
            Button("Preview \(voice.name)") { onPreview() }
        }
    }
}

// MARK: - Step 3: Add account

struct AddAccountStep: View {
    let advance: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var showSetup = false

    var body: some View {
        OnboardingStepShell(
            icon: "envelope.badge.fill",
            title: "Connect Your Email",
            subtitle: "Aria supports Gmail, Outlook, iCloud, Yahoo, and any IMAP provider.",
            primaryLabel: appState.accounts.isEmpty ? "Add My First Account" : "Continue",
            primaryAction: { appState.accounts.isEmpty ? (showSetup = true) : advance() },
            skipLabel: "Skip for now",
            skipAction: advance
        ) {
            VStack(spacing: 14) {
                if !appState.accounts.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(appState.accounts) { acc in
                            HStack {
                                Image(systemName: acc.provider.iconName)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(acc.displayName).fontWeight(.medium)
                                    Text(acc.emailAddress).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("\(acc.displayName), \(acc.emailAddress), connected")
                        }
                        Button("Add another account") { showSetup = true }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    HStack(spacing: 20) {
                        ForEach([EmailProvider.gmail, .outlook, .icloud], id: \.self) { p in
                            VStack(spacing: 6) {
                                Image(systemName: p.iconName)
                                    .font(.largeTitle)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                                Text(p.rawValue)
                                    .font(.caption)
                            }
                            .accessibilityLabel(p.rawValue)
                        }
                        Text("+ more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showSetup, onDismiss: {
            if !appState.accounts.isEmpty { advance() }
        }) {
            AccountSetupView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Step 4: macOS Mail import

struct MailImportStep: View {
    let advance: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var importable = MacMailImporter.importAccounts()
    @State private var imported = false

    var body: some View {
        if importable.isEmpty {
            // No macOS Mail accounts — skip silently
            Color.clear
                .onAppear { advance() }
        } else {
            OnboardingStepShell(
                icon: "arrow.down.circle.fill",
                title: "Import from Mail",
                subtitle: "Aria found \(importable.count) account\(importable.count == 1 ? "" : "s") already on your Mac. Import them in one tap.",
                primaryLabel: imported ? "Continue" : "Import All",
                primaryAction: { imported ? advance() : importAll() },
                skipLabel: "Skip",
                skipAction: advance
            ) {
                VStack(spacing: 10) {
                    ForEach(importable, id: \.emailAddress) { config in
                        HStack {
                            Image(systemName: config.provider.iconName)
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(config.displayName).fontWeight(.medium)
                                Text(config.emailAddress).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if imported {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("\(config.displayName), \(config.emailAddress)")
                    }

                    Text("Your credentials stay on this Mac. Nothing is sent to any server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .accessibilityLabel("Privacy note: credentials stay on your Mac only.")
                }
            }
        }
    }

    private func importAll() {
        for config in importable {
            let acc = EmailAccount(
                displayName: config.displayName,
                emailAddress: config.emailAddress,
                provider: config.provider,
                imapHost: config.imapHost,
                imapPort: config.imapPort,
                smtpHost: config.smtpHost,
                smtpPort: config.smtpPort,
                importedFromMailApp: true
            )
            if !appState.accounts.contains(where: { $0.emailAddress == acc.emailAddress }) {
                appState.addAccount(acc)
            }
        }
        imported = true
        appState.speech.speak("Imported \(importable.count) account\(importable.count == 1 ? "" : "s") successfully.")
    }
}

// MARK: - Step 5: AI agent setup

struct AgentSetupStep: View {
    let advance: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var apiKey = ""
    @State private var saved = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        OnboardingStepShell(
            icon: "brain.head.profile",
            title: "Connect the AI Assistant",
            subtitle: "Aria uses Claude by Anthropic to understand your voice commands and help manage email.",
            primaryLabel: saved ? "Continue" : (apiKey.isEmpty ? "Skip for now" : "Save & Continue"),
            primaryAction: { saveAndAdvance() },
            skipLabel: nil,
            skipAction: nil
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anthropic API key")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SecureField("sk-ant-…", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .accessibilityLabel("Anthropic API key field")

                    Text("Your key is stored only in the macOS Keychain — never sent anywhere else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if saved {
                    Label("API key saved securely.", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("API key saved successfully in Keychain")
                }

                HStack(spacing: 6) {
                    Text("Need a key?")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Link("Get one at console.anthropic.com",
                         destination: URL(string: "https://console.anthropic.com")!)
                        .font(.callout)
                        .accessibilityLabel("Get an Anthropic API key — opens console.anthropic.com in browser")
                }
            }
        }
        .onAppear { fieldFocused = true }
    }

    private func saveAndAdvance() {
        if !apiKey.isEmpty {
            KeychainService.shared.save(key: "aria.anthropic.key", value: apiKey)
            saved = true
            appState.speech.speak("API key saved. The AI assistant is ready.")
        }
        advance()
    }
}

// MARK: - Step 6: Feature tour

struct FeatureTourStep: View {
    let advance: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var currentTip = 0

    let tips: [(icon: String, title: String, description: String)] = [
        ("mic.fill",          "Talk to Aria",          "Press ⌘⌥L or click the mic. Say \"Read my latest email\", \"Delete all spam\", or \"Unsubscribe from this list.\""),
        ("trash.fill",        "Bulk actions",          "Select emails with the spacebar, then say \"Delete selected\" or \"Archive selected\". Works on hundreds at once."),
        ("link",              "Voice link reader",     "When reading an email, say \"Read links\" to hear every link. Say a link's name to open it."),
        ("bell.slash.fill",   "Unsubscribe by voice",  "Say \"Unsubscribe\" on any promotional email. Aria finds the unsubscribe method and handles it for you."),
        ("calendar.badge.checkmark", "Meeting invites", "Say \"Accept\" or \"Decline\" on any calendar invite. Aria adds it to Calendar and can read the meeting link."),
        ("person.badge.plus", "Multiple accounts",     "Add as many Gmail, Outlook, iCloud, or IMAP accounts as you like from Settings > Accounts."),
    ]

    var body: some View {
        OnboardingStepShell(
            icon: "lightbulb.fill",
            title: "What Aria Can Do",
            subtitle: "Swipe or use arrow keys to browse. Press Continue when ready.",
            primaryLabel: currentTip < tips.count - 1 ? "Next tip" : "Continue",
            primaryAction: { currentTip < tips.count - 1 ? nextTip() : advance() },
            skipLabel: currentTip < tips.count - 1 ? "Skip tips" : nil,
            skipAction: currentTip < tips.count - 1 ? advance : nil
        ) {
            VStack(spacing: 20) {
                // Tip card
                let tip = tips[currentTip]
                VStack(spacing: 14) {
                    Image(systemName: tip.icon)
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(tip.title)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(tip.description)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(tip.title). \(tip.description)")
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(currentTip)

                // Dots
                HStack(spacing: 6) {
                    ForEach(0..<tips.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentTip ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityLabel("Tip \(currentTip + 1) of \(tips.count)")
            }
        }
    }

    private func nextTip() {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentTip = min(currentTip + 1, tips.count - 1)
        }
        appState.speech.speak(tips[currentTip].title + ". " + tips[currentTip].description)
    }
}

// MARK: - Step 7: Ready

struct ReadyStep: View {
    let finish: () -> Void
    @EnvironmentObject var appState: AppState

    var body: some View {
        OnboardingStepShell(
            icon: "checkmark.circle.fill",
            title: "You're All Set!",
            subtitle: "Aria is ready. Open your inbox and start managing email by voice.",
            primaryLabel: "Open My Inbox",
            primaryAction: finish
        ) {
            VStack(spacing: 10) {
                TipRow(key: "⌘⌥L", value: "Start / stop listening")
                TipRow(key: "⌘⌥A", value: "Toggle AI assistant")
                TipRow(key: "⌘A",  value: "Select all emails")
                TipRow(key: "⌘⌫", value: "Delete selected")
                TipRow(key: "⌘R",  value: "Reply")
                TipRow(key: "⌘⌥R", value: "Read aloud / stop")
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Quick keyboard shortcuts list")
        }
        .onAppear {
            appState.speech.speak("You are all set. Press Open My Inbox to get started.")
        }
    }
}

struct TipRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack {
            Text(key)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityLabel("\(key): \(value)")
    }
}
