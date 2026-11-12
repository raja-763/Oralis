import AVFoundation
import SwiftUI

/// Settings panel — three sections: AI, Voice, Reading.
struct VoiceSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var prefs         = VoicePreferencesStore.shared.current
    @State private var voices        = OralisVoice.allVoices(for: VoicePreferencesStore.shared.current.language)
    @State private var selectedVoiceID: String = VoicePreferencesStore.shared.current.voiceIdentifier
    @State private var previewText   = "Hello! I'm Oralis, your voice-first assistant."
    @State private var isPreviewing  = false
    @State private var filterQuality: FilterQuality = .all
    @State private var anthropicKey: String = UserDefaults.standard.string(forKey: "oralis.anthropicAPIKey") ?? ""
    @State private var anthropicWorkspace: String = UserDefaults.standard.string(forKey: "oralis.anthropicWorkspaceID") ?? ""
    @State private var keySaved      = false

    enum FilterQuality: String, CaseIterable, Identifiable {
        case all = "All", premium = "Premium", enhanced = "Enhanced", standard = "Standard"
        var id: String { rawValue }
    }

    var filteredVoices: [OralisVoice] {
        switch filterQuality {
        case .all:      return voices
        case .premium:  return voices.filter { $0.quality == .premium }
        case .enhanced: return voices.filter { $0.quality == .enhanced }
        case .standard: return voices.filter { $0.quality == .default }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── 1. Voice Preview (top — hear before you configure) ──
                sectionHeader("Voice Preview", icon: "play.circle.fill")
                previewPanel
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                sectionDivider

                // ── 2. Voice Options ───────────────────────────────────
                sectionHeader("Voice Options", icon: "waveform.circle.fill")
                VStack(alignment: .leading, spacing: 20) {
                    languageSection
                    if SpeechService.elevenLabsEnabled { elevenLabsSection }
                    voicePickerSection
                    voiceAdjustmentsSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                sectionDivider

                // ── 3. Reading Settings ────────────────────────────────
                sectionHeader("Reading Settings", icon: "book.fill")
                readingSettingsSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                sectionDivider

                // ── 4. AI (Anthropic) ──────────────────────────────────
                sectionHeader("AI — Anthropic", icon: "sparkles")
                aiKeySection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .onDisappear { save() }
    }

    // MARK: - Section chrome

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .font(.body.weight(.semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .frame(height: 1)
    }

    // MARK: - 1. Voice Preview

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type a sentence and press Play to hear how the current voice sounds.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Type something to hear…", text: $previewText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Preview text — type any sentence to hear it spoken")

                Button {
                    if isPreviewing {
                        appState.speech.stopSpeaking()
                        isPreviewing = false
                    } else {
                        isPreviewing = true
                        appState.speech.speak(previewText, prefs: prefs)
                    }
                } label: {
                    Label(isPreviewing ? "Stop" : "Play",
                          systemImage: isPreviewing ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(isPreviewing ? "Stop preview" : "Play voice preview")
            }
        }
        .onReceive(appState.speech.$isSpeaking) { speaking in
            if !speaking { isPreviewing = false }
        }
    }

    // MARK: - 2a. Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Language")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Sets both the listening language and the voice accent.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(SupportedLanguage.all) { lang in
                    Button {
                        prefs.language = lang.id
                        voices = OralisVoice.allVoices(for: lang.id)
                        if !voices.isEmpty && !voices.contains(where: { $0.id == selectedVoiceID }) {
                            selectedVoiceID = voices.first?.id ?? ""
                            prefs.voiceIdentifier = selectedVoiceID
                        }
                        save()
                    } label: {
                        HStack {
                            Text("\(lang.flag) \(lang.name)")
                            if prefs.language == lang.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                let selected = SupportedLanguage.find(prefs.language)
                menuPickerLabel("\(selected.flag) \(selected.name)")
            }
            .accessibilityLabel("Language: \(SupportedLanguage.find(prefs.language).name)")
        }
    }

    // MARK: - 2b. ElevenLabs

    private let elevenLabsVoices: [(id: String, name: String, description: String)] = [
        ("21m00Tcm4TlvDq8ikWAM", "Rachel",  "Calm · Natural · Female"),
        ("EXAVITQu4vr4xnSDxMaL", "Bella",   "Soft · Friendly · Female"),
        ("AZnzlk1XvdvUeBnXmlld", "Domi",    "Confident · Strong · Female"),
        ("MF3mGyEYCl7XYWbV9V6O", "Elli",    "Warm · Expressive · Female"),
        ("ErXwobaYiN019PkySvjV", "Antoni",  "Natural · Well-rounded · Male"),
        ("TxGEqnHWrfWFTfGW9XjX", "Josh",    "Deep · Young · Male"),
        ("VR6AewLTigWG4xSOukaG", "Arnold",  "Crisp · Authoritative · Male"),
        ("pNInz6obpgDQGcFmaJgB", "Adam",    "Deep · US · Male"),
        ("yoZ06aMxZJJ28mfd3POQ", "Sam",     "Raspy · Casual · Male"),
    ]

    private var elevenLabsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("ElevenLabs AI Voice")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("ACTIVE")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }

            Toggle("Use ElevenLabs voice", isOn: $prefs.useElevenLabs)
                .onChange(of: prefs.useElevenLabs) { _, _ in save() }

            if prefs.useElevenLabs {
                Menu {
                    ForEach(elevenLabsVoices, id: \.id) { voice in
                        Button {
                            prefs.elevenLabsVoiceID = voice.id
                            previewElevenLabs(voice.id)
                        } label: {
                            HStack {
                                Text("\(voice.name) — \(voice.description)")
                                if prefs.elevenLabsVoiceID == voice.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    let sel = elevenLabsVoices.first(where: { $0.id == prefs.elevenLabsVoiceID })
                    menuPickerLabel(sel?.name ?? "Choose a voice", subtitle: sel?.description)
                }
                .accessibilityLabel("ElevenLabs voice: \(elevenLabsVoices.first(where: { $0.id == prefs.elevenLabsVoiceID })?.name ?? "none")")
            }
        }
    }

    // MARK: - 2c. Apple voice picker

    private var voicePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apple Voice")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker("Quality", selection: $filterQuality) {
                    ForEach(FilterQuality.allCases) { q in Text(q.rawValue).tag(q) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Filter voices by quality")
            }

            Menu {
                ForEach(filteredVoices) { voice in
                    Button {
                        selectedVoiceID = voice.id
                        prefs.voiceIdentifier = voice.id
                        previewVoice(id: voice.id)
                    } label: {
                        HStack {
                            Text(voice.name)
                            if voice.id == selectedVoiceID { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                let sel = filteredVoices.first(where: { $0.id == selectedVoiceID })
                menuPickerLabel(sel?.name ?? "Choose a voice", subtitle: sel?.language)
            }
            .accessibilityLabel("Selected voice: \(filteredVoices.first(where: { $0.id == selectedVoiceID })?.name ?? "none")")

            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!)
            } label: {
                Label("Download more voices in System Settings…", systemImage: "arrow.down.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - 2d. Speed / pitch / volume sliders

    private var voiceAdjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Adjustments")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LabeledSlider(label: "Reading speed",
                          value: $prefs.rate,
                          range: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate,
                          leftLabel: "Slow", rightLabel: "Fast")
            .onChange(of: prefs.rate) { _, _ in previewCurrentSettings() }

            LabeledSlider(label: "Voice pitch",
                          value: $prefs.pitch,
                          range: 0.5...2.0,
                          leftLabel: "Low", rightLabel: "High")
            .onChange(of: prefs.pitch) { _, _ in previewCurrentSettings() }

            LabeledSlider(label: "Volume",
                          value: $prefs.volume,
                          range: 0.1...1.0,
                          leftLabel: "Quiet", rightLabel: "Loud")
        }
        .onChange(of: prefs) { _, _ in save() }
    }

    // MARK: - 3. Reading Settings

    private var readingSettingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── Email reading order ────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Email Reading Order")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose the order in which Oralis reads each email's fields aloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Email reading order", selection: $prefs.emailReadOrder) {
                    ForEach(EmailReadOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Email reading order: \(prefs.emailReadOrder.rawValue)")
                .onChange(of: prefs.emailReadOrder) { _, _ in save() }
            }

            Divider()

            // ── Response length ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Response Length")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Controls how much Oralis speaks after a voice command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Response length", selection: $prefs.responseLength) {
                    ForEach(ResponseLength.allCases) { len in
                        Text(len.rawValue).tag(len)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: prefs.responseLength) { _, _ in save() }
            }

            Divider()

            // ── Reading toggles ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Reading Behaviour")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 12) {
                    Toggle("Read email summary only (AI-generated)",
                           isOn: $prefs.readEmailSummaryOnly)
                        .accessibilityLabel("Ask the AI to summarize each email instead of reading the full body")

                    Toggle("Read new emails automatically on open",
                           isOn: $prefs.autoReadNewEmails)
                        .accessibilityLabel("Automatically read each email aloud when you open it")

                    Toggle("Announce sender name",
                           isOn: $prefs.readSenderName)
                        .accessibilityLabel("Say the sender's name before reading the email body")

                    Toggle("Announce received date",
                           isOn: $prefs.readDate)
                        .accessibilityLabel("Say when the email was received")

                    Toggle("Announce batch action results",
                           isOn: $prefs.announceBatchResults)
                        .accessibilityLabel("Speak a summary after bulk delete, archive, or unsubscribe")
                }
            }
            .onChange(of: prefs) { _, _ in save() }
        }
    }

    // MARK: - 4. AI key section

    private var aiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your AI key powers voice commands, email summaries, and smart replies.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    TextField("sk-ant-…", text: $anthropicKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Anthropic API key")
                        .onChange(of: anthropicKey) { _, new in
                            UserDefaults.standard.set(
                                new.trimmingCharacters(in: .whitespacesAndNewlines),
                                forKey: "oralis.anthropicAPIKey")
                            keySaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
                        }
                    if keySaved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale)
                    }
                }
                if anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("No key — voice commands won't work until you add one.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Workspace ID")
                    .font(.subheadline.weight(.medium))
                HStack {
                    TextField("wrkspc_…", text: $anthropicWorkspace)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .accessibilityLabel("Anthropic workspace ID")
                        .onChange(of: anthropicWorkspace) { _, new in
                            UserDefaults.standard.set(
                                new.trimmingCharacters(in: .whitespacesAndNewlines),
                                forKey: "oralis.anthropicWorkspaceID")
                        }
                }
                Text("Required for workspace API keys (sk-ant-usr-…). Find it at console.anthropic.com → Settings → Workspaces.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                NSWorkspace.shared.open(URL(string: "https://console.anthropic.com/settings/keys")!)
            } label: {
                Label("Get an API key at console.anthropic.com…", systemImage: "arrow.up.right.square")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Shared picker label

    private func menuPickerLabel(_ title: String, subtitle: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func previewVoice(id: String) {
        var p = prefs; p.voiceIdentifier = id
        appState.speech.speak(previewText, prefs: p)
        isPreviewing = true
    }

    private func previewCurrentSettings() {
        guard !previewText.isEmpty else { return }
        appState.speech.speak(previewText, prefs: prefs)
        isPreviewing = true
    }

    private func previewElevenLabs(_ voiceID: String) {
        var p = prefs; p.useElevenLabs = true; p.elevenLabsVoiceID = voiceID
        let name = elevenLabsVoices.first(where: { $0.id == voiceID })?.name ?? "this voice"
        appState.speech.speak("Hi, I'm \(name).", prefs: p)
        isPreviewing = true
    }

    private func save() {
        appState.speech.preferences = prefs
        VoicePreferencesStore.shared.current = prefs
    }
}

// MARK: - Labelled slider

struct LabeledSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let leftLabel: String
    let rightLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            HStack {
                Text(leftLabel).font(.caption).foregroundStyle(.secondary)
                Slider(value: $value, in: range)
                    .accessibilityLabel(label)
                    .accessibilityValue(String(format: "%.0f%%",
                        (value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100))
                Text(rightLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
