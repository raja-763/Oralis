import AVFoundation
import SwiftUI

/// Full voice customisation panel.
/// Accessible via Settings menu or the Onboarding voice step.
struct VoiceSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var prefs = VoicePreferencesStore.shared.current
    @State private var voices = OralisVoice.allEnglishVoices()
    @State private var selectedVoiceID: String = VoicePreferencesStore.shared.current.voiceIdentifier
    @State private var previewText = "Hello! I'm Oralis, your voice-first email assistant."
    @State private var isPreviewing = false
    @State private var filterQuality: FilterQuality = .all

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
        HSplitView {
            // Left: voice list
            voiceListPanel
                .frame(minWidth: 260, maxWidth: 320)

            // Right: controls + preview
            VStack(alignment: .leading, spacing: 0) {
                controlsPanel
                Divider()
                previewPanel
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .navigationTitle("Voice Settings")
        .onDisappear { save() }
    }

    // MARK: - Voice list

    private var voiceListPanel: some View {
        VStack(spacing: 0) {
            // Quality filter
            Picker("Show", selection: $filterQuality) {
                ForEach(FilterQuality.allCases) { q in
                    Text(q.rawValue).tag(q)
                }
            }
            .pickerStyle(.segmented)
            .padding(10)
            .accessibilityLabel("Filter voices by quality")

            Divider()

            List(filteredVoices, selection: $selectedVoiceID) { voice in
                VoiceRow(voice: voice, isSelected: voice.id == selectedVoiceID)
                    .tag(voice.id)
            }
            .listStyle(.sidebar)
            .onChange(of: selectedVoiceID) { _, id in
                prefs.voiceIdentifier = id
                previewVoice(id: id)
            }

            Divider()
            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!)
            } label: {
                Label("Download more voices…", systemImage: "arrow.down.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(10)
            .accessibilityLabel("Open System Settings to download additional voices")
        }
    }

    // MARK: - Controls

    private var controlsPanel: some View {
        Form {
            Section("Speed") {
                LabeledSlider(
                    label: "Reading speed",
                    value: $prefs.rate,
                    range: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate,
                    leftLabel: "Slow", rightLabel: "Fast"
                )
                .onChange(of: prefs.rate) { _, _ in previewCurrentSettings() }
            }

            Section("Pitch") {
                LabeledSlider(
                    label: "Voice pitch",
                    value: $prefs.pitch,
                    range: 0.5...2.0,
                    leftLabel: "Low", rightLabel: "High"
                )
                .onChange(of: prefs.pitch) { _, _ in previewCurrentSettings() }
            }

            Section("Volume") {
                LabeledSlider(
                    label: "Volume",
                    value: $prefs.volume,
                    range: 0.1...1.0,
                    leftLabel: "Quiet", rightLabel: "Loud"
                )
            }

            Section("Reading options") {
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
        .formStyle(.grouped)
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
