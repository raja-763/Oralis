import AVFoundation
import Speech
import SwiftUI

/// Handles both text-to-speech (reading emails aloud) and
/// speech-to-text (voice commands / dictation).
///
/// TTS engine priority:
///   1. ElevenLabs via proxy (if proxyURL is set in VoicePreferences)
///   2. Apple AVSpeechSynthesizer (Enhanced/Premium voices preferred)
@MainActor
final class SpeechService: NSObject, ObservableObject {

    // MARK: - TTS

    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    private var audioPlayer: AVAudioPlayer?

    // ElevenLabs TTS proxy URL — set in VoicePreferencesStore
    // Format: https://oralis-tts.YOUR_SUBDOMAIN.workers.dev/tts
    // Leave empty to use Apple voices.
    static let elevenLabsProxyURL: String = {
        Bundle.main.infoDictionary?["ELEVENLABS_PROXY_URL"] as? String ?? ""
    }()

    /// Stable device identifier for rate limiting
    private var deviceID: String {
        if let stored = UserDefaults.standard.string(forKey: "oralis.deviceID") { return stored }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "oralis.deviceID")
        return id
    }

    /// Live preferences — updated by VoiceSettingsView without restarting the service.
    var preferences: VoicePreferences = VoicePreferencesStore.shared.current

    func speak(_ text: String) {
        speak(text, prefs: preferences)
    }

    func speak(_ text: String, prefs: VoicePreferences) {
        stopSpeaking()

        // Try ElevenLabs if a voice ID is selected and proxy is configured
        if prefs.useElevenLabs, !prefs.elevenLabsVoiceID.isEmpty,
           !SpeechService.elevenLabsProxyURL.isEmpty {
            Task { await speakElevenLabs(text, voiceID: prefs.elevenLabsVoiceID) }
        } else {
            speakApple(text, prefs: prefs)
        }
    }

    // MARK: - Apple TTS

    private func speakApple(_ text: String, prefs: VoicePreferences) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate             = prefs.rate
        utterance.pitchMultiplier  = prefs.pitch
        utterance.volume           = prefs.volume
        // Prefer a Premium voice if none explicitly chosen
        if prefs.voiceIdentifier.isEmpty {
            utterance.voice = bestAvailableAppleVoice()
        } else {
            utterance.voice = AVSpeechSynthesisVoice(identifier: prefs.voiceIdentifier)
                           ?? bestAvailableAppleVoice()
        }
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Returns the best available Apple voice (Premium > Enhanced > default en-US).
    static func bestAvailableAppleVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        return voices.first(where: { $0.quality == .premium })
            ?? voices.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func bestAvailableAppleVoice() -> AVSpeechSynthesisVoice? {
        SpeechService.bestAvailableAppleVoice()
    }

    // MARK: - ElevenLabs TTS

    private func speakElevenLabs(_ text: String, voiceID: String) async {
        guard let url = URL(string: SpeechService.elevenLabsProxyURL) else { return }

        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
            req.httpBody = try JSONEncoder().encode(["text": text, "voice_id": voiceID])

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // Fall back to Apple on error
                speakApple(text, prefs: preferences)
                return
            }

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = audioDelegate
            audioPlayer?.play()
            isSpeaking = true
        } catch {
            speakApple(text, prefs: preferences)
        }
    }

    private lazy var audioDelegate = AudioPlayerDelegate { [weak self] in
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
    }

    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
        audioPlayer?.pause()
    }

    func resumeSpeaking() {
        synthesizer.continueSpeaking()
        audioPlayer?.play()
    }

    // MARK: - STT (voice commands)

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    @Published var isListening = false
    @Published var transcribedText = ""
    var onFinalResult: ((String) -> Void)?

    func requestPermissions() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func startListening() throws {
        guard !isListening else { return }

        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let req = recognitionRequest else { return }
        req.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcribedText = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.onFinalResult?(result.bestTranscription.formattedString)
                    }
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in self.stopListening() }
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                             didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in isSpeaking = false }
    }
}

// MARK: - AVAudioPlayer delegate helper

final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    init(_ onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
