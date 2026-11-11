import AVFoundation
import SwiftUI

/// Full voice customisation panel.
/// Accessible via Settings menu or the Onboarding voice step.
struct VoiceSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var prefs = VoicePreferencesStore.shared.current
    @State private var voices = OralisVoice.allVoices(for: VoicePreferencesStore.shared.current.language)
    @State private var selectedVoiceID: String = VoicePreferencesStore.shared.current.voiceIdentifier
    @State private var previewText = "Hello! I'm Oralis, your voice-first email assistant."
    @State private var isPreviewing = false
    @State private var filterQuality: FilterQuality = .all
    @State private var anthropicKey: String = UserDefaults.standard.string(forKey: "oralis.anthropicAPIKey") ?? ""
    @State private var keySaved = false

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
            VStack(alignment: .leading, spacing: 24) {
                // ── Anthropic API key ───────────────────────────────
                aiKeySection

                Divider()

                // ── Language picker ─────────────────────────────────
                languageSection

                Divider()

                // ── ElevenLabs voices (shown when API key is active) ─
                if SpeechService.elevenLabsEnabled {
                    elevenLabsSection
                    Divider()
                }

                // ── Apple voice picker ───────────────────────────────
                voicePickerSection

                Divider()

                // ── Sliders + toggles ───────────────────────────────
                controlsInline

                Divider()

                // ── Preview ─────────────────────────────────────────
                previewPanel
            }
            .padding(24)
        }
        .onDisappear { save() }
    }

    // MARK: - AI key section

    private var aiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI (Anthropic)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Paste your key below — it saves automatically as you type.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("sk-ant-…", text: $anthropicKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Anthropic API key")
                    .onChange(of: anthropicKey) { _, new in
                        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                        UserDefaults.standard.set(trimmed, forKey: "oralis.anthropicAPIKey")
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
                Text("⚠ No key — voice commands won't work until you add one.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Language section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversation Language")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Oralis listens and responds in this language. Works with both Apple and ElevenLabs voices.")
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
                            if prefs.language == lang.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selected = SupportedLanguage.find(prefs.language)
                HStack {
                    Text("\(selected.flag) \(selected.name)")
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Language: \(SupportedLanguage.find(prefs.language).name). Tap to change.")
        }
    }

    // MARK: - ElevenLabs section

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("ElevenLabs AI Voices")
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
                .accessibilityLabel("Toggle ElevenLabs AI voice on or off")

            if prefs.useElevenLabs {
                Menu {
                    ForEach(elevenLabsVoices, id: \.id) { voice in
                        Button {
                            prefs.elevenLabsVoiceID = voice.id
                            previewElevenLabs(voice.id)
                        } label: {
                            HStack {
                                Text("\(voice.name) — \(voice.description)")
                                if prefs.elevenLabsVoiceID == voice.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            let selected = elevenLabsVoices.first(where: { $0.id == prefs.elevenLabsVoiceID })
                            Text(selected?.name ?? "Choose a voice")
                                .fontWeight(.medium)
                            Text(selected?.description ?? "Tap to pick an ElevenLabs voice")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("ElevenLabs voice: \(elevenLabsVoices.first(where: { $0.id == prefs.elevenLabsVoiceID })?.name ?? "none"). Tap to change.")
            }
        }
    }

    // MARK: - Voice picker (flat list — no nested HSplitView)

    private var voicePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Voice")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                // Quality filter
                Picker("Filter", selection: $filterQuality) {
                    ForEach(FilterQuality.allCases) { q in
                        Text(q.rawValue).tag(q)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Filter voices by quality")
            }

            // Voice menu — accessible popup, no trapped List
            Menu {
                ForEach(filteredVoices) { voice in
                    Button {
                        selectedVoiceID = voice.id
                        prefs.voiceIdentifier = voice.id
                        previewVoice(id: voice.id)
                    } label: {
                        HStack {
                            Text(voice.name)
                            if voice.id == selectedVoiceID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(filteredVoices.first(where: { $0.id == selectedVoiceID })?.name ?? "Choose a voice")
                            .fontWeight(.medium)
                        Text(filteredVoices.first(where: { $0.id == selectedVoiceID })?.language ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Selected voice: \(filteredVoices.first(where: { $0.id == selectedVoiceID })?.name ?? "none"). Tap to change.")

            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!)
            } label: {
                Label("Download more voices in System Settings…", systemImage: "arrow.down.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Open System Settings to download additional voices")
        }
    }

    // MARK: - Controls (inline, no Form with grouped style that traps focus)

    private var controlsInline: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Adjustments")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LabeledSlider(
                label: "Reading speed",
                value: $prefs.rate,
                range: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate,
                leftLabel: "Slow", rightLabel: "Fast"
            )
            .onChange(of: prefs.rate) { _, _ in previewCurrentSettings() }

            LabeledSlider(
                label: "Voice pitch",
                value: $prefs.pitch,
                range: 0.5...2.0,
                leftLabel: "Low", rightLabel: "High"
            )
            .onChange(of: prefs.pitch) { _, _ in previewCurrentSettings() }

            LabeledSlider(
                label: "Volume",
                value: $prefs.volume,
                range: 0.1...1.0,
                leftLabel: "Quiet", rightLabel: "Loud"
            )

            Divider()

            Text("Reading Options")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 14) {
                Toggle("Read new emails automatically", isOn: $prefs.autoReadNewEmails)
                    .accessibilityLabel("Automatically read each email aloud when you open it")
                Toggle("Include sender name", isOn: $prefs.readSenderName)
                    .accessibilityLabel("Say the sender's name before reading the email body")
                Toggle("Include received date", isOn: $prefs.readDate)
                    .accessibilityLabel("Say when the email was received")
                Toggle("Announce batch action results", isOn: $prefs.announceBatchResults)
                    .accessibilityLabel("Speak a summary after bulk delete, archive, or unsubscribe")
            }
        }
        .onChange(of: prefs) { _, _ in save() }
    }

    // MARK: - Preview

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal)
                .padding(.top, 12)

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
                .keyboardShortcut(.space, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .onReceive(appState.speech.$isSpeaking) { speaking in
            if !speaking { isPreviewing = false }
        }
    }

    // MARK: - Helpers

    private func previewVoice(id: String) {
        var p = prefs
        p.voiceIdentifier = id
        appState.speech.speak(previewText, prefs: p)
        isPreviewing = true
    }

    private func previewCurrentSettings() {
        guard !previewText.isEmpty else { return }
        appState.speech.speak(previewText, prefs: prefs)
        isPreviewing = true
    }

    private func previewElevenLabs(_ voiceID: String) {
        var p = prefs
        p.useElevenLabs = true
        p.elevenLabsVoiceID = voiceID
        appState.speech.speak("Hi, I'm \(elevenLabsVoices.first(where: { $0.id == voiceID })?.name ?? "your Oralis voice").", prefs: p)
        isPreviewing = true
    }

    private func save() {
        appState.speech.preferences = prefs
        VoicePreferencesStore.shared.current = prefs
    }
}

// MARK: - Voice row

struct VoiceRow: View {
    let voice: OralisVoice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(voice.language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(voice.qualityLabel)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(qualityColor(voice.quality).opacity(0.18))
                .foregroundStyle(qualityColor(voice.quality))
                .clipShape(Capsule())
        }
        .accessibilityLabel("\(voice.name), \(voice.language), \(voice.qualityLabel) quality")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func qualityColor(_ q: AVSpeechSynthesisVoiceQuality) -> Color {
        switch q {
        case .premium:  return .yellow
        case .enhanced: return .blue
        default:        return .secondary
        }
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
            HStack {
                Text(leftLabel).font(.caption).foregroundStyle(.secondary)
                Slider(value: $value, in: range)
                    .accessibilityLabel(label)
                    .accessibilityValue(String(format: "%.0f%%", (value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100))
                Text(rightLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
