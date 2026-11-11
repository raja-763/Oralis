import AppKit
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

    // ElevenLabs direct API key (compiled in via Secrets.xcconfig, never in git)
    static let elevenLabsAPIKey: String = {
        Bundle.main.infoDictionary?["ELEVENLABS_API_KEY"] as? String ?? ""
    }()

    // Optional proxy URL — takes precedence over direct key if set
    static let elevenLabsProxyURL: String = {
        Bundle.main.infoDictionary?["ELEVENLABS_PROXY_URL"] as? String ?? ""
    }()

    static var elevenLabsEnabled: Bool {
        !elevenLabsAPIKey.isEmpty || !elevenLabsProxyURL.isEmpty
    }

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

        // Try ElevenLabs if a voice ID is selected and API key or proxy is configured
        if prefs.useElevenLabs, !prefs.elevenLabsVoiceID.isEmpty,
           SpeechService.elevenLabsEnabled {
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
        if prefs.voiceIdentifier.isEmpty {
            utterance.voice = bestVoiceForLanguage(prefs.language)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(identifier: prefs.voiceIdentifier)
                           ?? bestVoiceForLanguage(prefs.language)
        }
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Best available Apple voice for a locale (Premium > Enhanced > any match).
    static func bestVoiceForLanguage(_ locale: String) -> AVSpeechSynthesisVoice? {
        let prefix = locale.split(separator: "-").first.map(String.init) ?? locale
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        return voices.first(where: { $0.quality == .premium })
            ?? voices.first(where: { $0.quality == .enhanced })
            ?? voices.first
            ?? AVSpeechSynthesisVoice(language: locale)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    static func bestAvailableAppleVoice() -> AVSpeechSynthesisVoice? {
        bestVoiceForLanguage("en-US")
    }

    private func bestVoiceForLanguage(_ locale: String) -> AVSpeechSynthesisVoice? {
        SpeechService.bestVoiceForLanguage(locale)
    }

    private func bestAvailableAppleVoice() -> AVSpeechSynthesisVoice? {
        SpeechService.bestAvailableAppleVoice()
    }

    // MARK: - ElevenLabs TTS

    private func speakElevenLabs(_ text: String, voiceID: String) async {
        // Use proxy if configured, otherwise call ElevenLabs API directly
        let useProxy = !SpeechService.elevenLabsProxyURL.isEmpty
        let urlString = useProxy
            ? SpeechService.elevenLabsProxyURL
            : "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)"

        guard let url = URL(string: urlString) else { return }

        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if useProxy {
                req.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
                req.httpBody = try JSONEncoder().encode(["text": text, "voice_id": voiceID])
            } else {
                req.setValue(SpeechService.elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
                let body: [String: Any] = [
                    "text": text,
                    "model_id": "eleven_multilingual_v2",
                    "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
            }

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
        // Request speech recognition permission.
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }

        // Request microphone permission.
        return await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    var permissionsGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized &&
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func startListening(locale: String = "en-US") throws {
        guard !isListening else { return }

        // Re-create engine every session — reusing a stopped engine can deadlock on some Macs.
        audioEngine = AVAudioEngine()

        recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        guard let recognizer, recognizer.isAvailable else {
            throw OralisError.apiError("Speech recognition is unavailable for \(locale).")
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let req = recognitionRequest else { return }
        req.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        // Use inputFormat (not outputFormat) for the microphone tap.
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw OralisError.apiError("No audio input device found. Check System Settings → Sound → Input.")
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        // Mic-on sound
        NSSound(named: .init("Ping"))?.play()

        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
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
        guard isListening else { return }
        // Mic-off sound
        NSSound(named: .init("Pop"))?.play()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        transcribedText = ""
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
