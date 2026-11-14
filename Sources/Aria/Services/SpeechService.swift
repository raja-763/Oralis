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
    private var speakingTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - VoiceOver detection

    /// True when VoiceOver is running. When true, we route all speech through
    /// VoiceOver announcements instead of AVSpeechSynthesizer so the two TTS
    /// engines don't fight each other.
    static var isVoiceOverActive: Bool {
        UserDefaults(suiteName: "com.apple.universalaccess")?
            .bool(forKey: "voiceOverOnOffKey") ?? false
    }

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
        isSpeaking = true
        spokenText = text

        // Always speak with Oralis's own voice, VoiceOver or not. VoiceOver announcements
        // proved unreliable (silent, or cut off by VoiceOver's own focus speech).
        // The timeout frees the conversation loop if didFinish never fires.
        let timeoutSecs = max(Double(text.count) / 12.0 + 6.0, 10.0)
        speakingTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSecs * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            oralisLog("speech: finish signal never arrived, released by timeout after \(Int(timeoutSecs))s")
            self.isSpeaking = false
        }

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
        // isSpeaking already set to true in speak() before calling here
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
            // isSpeaking already set to true in speak() before this Task ran
        } catch {
            speakApple(text, prefs: preferences)
        }
    }

    private lazy var audioDelegate = AudioPlayerDelegate { [weak self] in
        Task { @MainActor [weak self] in
            self?.speakingTimeoutTask?.cancel()
            self?.speakingTimeoutTask = nil
            self?.isSpeaking = false
        }
    }

    func stopSpeaking() {
        speakingTimeoutTask?.cancel()
        speakingTimeoutTask = nil
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

    // MARK: - Talking over Oralis (barge-in)
    // While Oralis speaks, the microphone stays open with echo cancellation. If the user
    // says something that is not what Oralis itself is saying, speech is cut off at once
    // and what they say becomes the next command.
    /// True while listening only to detect an interruption; nothing heard is treated as a command yet.
    private(set) var bargeInPending = false
    private var spokenText = ""
    /// Called the moment the user interrupts, so pending actions can be dropped.
    var onBargeIn: ((String) -> Void)?
    /// Words heard before the interruption (Oralis's echo, background sound) that are not part of the command.
    private var bargeInSkipWords = 0
    static var talkOverEnabled: Bool {
        UserDefaults.standard.object(forKey: "oralis.talkOver") as? Bool ?? true
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Index of the first word that Oralis is not saying itself, or nil if all of it is echo.
    private func firstNovelWordIndex(in heard: String) -> Int? {
        let spoken = Set(spokenText.split(whereSeparator: { $0.isWhitespace }).map { SpeechService.normalized(String($0)) })
        let words = heard.split(whereSeparator: { $0.isWhitespace }).map { SpeechService.normalized(String($0)) }
        return words.firstIndex { !$0.isEmpty && !spoken.contains($0) }
    }

    /// Strict on purpose: background voices and TV must not count. Either a clear
    /// stop word, or a real phrase of several words Oralis is not saying itself.
    private func isInterruption(_ heard: String) -> Bool {
        guard let start = firstNovelWordIndex(in: heard) else { return false }
        let words = heard.split(whereSeparator: { $0.isWhitespace }).map { SpeechService.normalized(String($0)) }
        let novel = words[start...].filter { !$0.isEmpty }
        let stopWords: Set<String> = ["stop", "wait", "pause", "cancel", "hold", "quiet", "enough"]
        return novel.count >= 4 || novel.contains(where: stopWords.contains)
    }

    /// The command without the words heard before the interruption.
    private func commandText(from heard: String) -> String {
        guard bargeInSkipWords > 0 else { return heard }
        let parts = heard.split(whereSeparator: { $0.isWhitespace })
        return parts.dropFirst(bargeInSkipWords).joined(separator: " ")
    }
    var onFinalResult: ((String) -> Void)?
    var onListeningStopped: (() -> Void)?
    private var silenceTask: Task<Void, Never>?

    // MARK: - Wake word detection ("Hey Oralis" / "Oralis")

    private var wakeEngine = AVAudioEngine()
    private var wakeRequest: SFSpeechAudioBufferRecognitionRequest?
    private var wakeTask: SFSpeechRecognitionTask?
    private var wakeRestartTimer: Timer?
    private(set) var isWakeWordActive = false
    private var wakeTapInstalled = false
    var onWakeWordDetected: (() -> Void)?

    func startWakeWordDetection() {
        guard !isWakeWordActive, permissionsGranted else { return }
        isWakeWordActive = true
        startOneWakeWordSession()
        // SFSpeechRecognizer tasks time out after ~60 s — restart every 55 s
        wakeRestartTimer = Timer.scheduledTimer(withTimeInterval: 55, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isWakeWordActive, !self.isListening else { return }
                self.stopOneWakeWordSession()
                self.startOneWakeWordSession()
            }
        }
    }

    func stopWakeWordDetection() {
        isWakeWordActive = false
        wakeRestartTimer?.invalidate()
        wakeRestartTimer = nil
        stopOneWakeWordSession()
    }

    private func startOneWakeWordSession() {
        guard !isListening else { return }
        wakeEngine = AVAudioEngine()
        let wakeRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let wakeRecognizer, wakeRecognizer.isAvailable else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        wakeRequest = req
        let inputNode = wakeEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }
        wakeTapInstalled = true
        // Start wake engine off main thread for the same reason as startListening
        let capturedWakeEngine = wakeEngine
        Task.detached(priority: .background) { try? capturedWakeEngine.start() }
        wakeTask = wakeRecognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString.lowercased() {
                let triggers = ["oralis", "hey oralis", "orales", "aurelius", "hey aurelius"]
                if triggers.contains(where: { text.contains($0) }) {
                    Task { @MainActor [weak self] in
                        guard let self, !self.isListening else { return }
                        self.stopOneWakeWordSession()
                        self.onWakeWordDetected?()
                    }
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor [weak self] in
                    guard let self, self.isWakeWordActive, !self.isListening else { return }
                    self.stopOneWakeWordSession()
                    self.startOneWakeWordSession()
                }
            }
        }
    }

    private func stopOneWakeWordSession() {
        // Only touch the engine if a session really started. Asking a never-started
        // engine for its inputNode blocks the main thread indefinitely, which froze the
        // app whenever wake word was disabled (it is disabled under VoiceOver).
        guard wakeTapInstalled else { return }
        wakeTapInstalled = false
        wakeEngine.stop()
        wakeEngine.inputNode.removeTap(onBus: 0)
        wakeRequest?.endAudio()
        wakeTask?.cancel()
        wakeRequest = nil
        wakeTask = nil
    }

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

    func startListening(locale: String = "en-US", bargeIn: Bool = false) async throws {
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
        // On-device recognition answers faster and works offline.
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }

        let inputNode = audioEngine.inputNode
        if bargeIn {
            // Echo cancellation, so Oralis's own voice from the speakers is not heard as the user.
            do { try inputNode.setVoiceProcessingEnabled(true) }
            catch { oralisLog("speech: echo cancellation unavailable: \(error.localizedDescription)") }
        }
        // Use inputFormat (not outputFormat) for the microphone tap.
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw OralisError.apiError("No audio input device found. Check System Settings → Sound → Input.")
        }
        // Echo cancellation delivers a many-channel buffer; the recognizer needs plain mono,
        // so only the processed first channel is passed on.
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            if bargeIn, buffer.format.channelCount > 1, let monoFormat,
               let source = buffer.floatChannelData,
               let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength),
               let target = mono.floatChannelData {
                mono.frameLength = buffer.frameLength
                memcpy(target[0], source[0], Int(buffer.frameLength) * MemoryLayout<Float>.size)
                req.append(mono)
            } else {
                req.append(buffer)
            }
        }

        audioEngine.prepare()
        // Start the audio engine off the main thread so VoiceOver accessibility events
        // are not blocked (VoiceOver marks the app "not responding" if the main thread
        // is busy with audio I/O for more than ~2 seconds).
        let engine = audioEngine
        try await Task.detached(priority: .userInitiated) { try engine.start() }.value

        isListening = true
        bargeInPending = bargeIn
        bargeInSkipWords = 0
        if bargeIn { oralisLog("speech: interruption listener on (format \(Int(format.sampleRate)) Hz, \(format.channelCount) ch)") }

        // Mic-on sound (not for the silent interruption listener)
        if !bargeIn { NSSound(named: .init("Ping"))?.play() }

        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    let raw = result.bestTranscription.formattedString
                    if self.bargeInPending {
                        // Only a deliberate interruption counts; echo and background sound are ignored.
                        guard self.isInterruption(raw) else {
                            oralisLog("speech: ignored sound while speaking (\(raw.count) characters)")
                            return
                        }
                        oralisLog("speech: interrupted by the user")
                        self.bargeInPending = false
                        // Everything heard before the first real word is echo or background.
                        self.bargeInSkipWords = self.firstNovelWordIndex(in: raw) ?? 0
                        self.onBargeIn?(self.commandText(from: raw))
                        self.stopSpeaking()
                    }
                    let heard = self.commandText(from: raw)
                    self.transcribedText = heard
                    // The recognizer never finalizes on its own while the mic stays open,
                    // so treat one second without new words as the end of the command.
                    if !result.isFinal, !self.transcribedText.isEmpty {
                        self.silenceTask?.cancel()
                        self.silenceTask = Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            guard let self, !Task.isCancelled, self.isListening else { return }
                            self.recognitionRequest?.endAudio()
                        }
                    }
                    if result.isFinal {
                        self.silenceTask?.cancel()
                        self.onFinalResult?(self.commandText(from: result.bestTranscription.formattedString))
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
        silenceTask?.cancel()
        silenceTask = nil
        // Mic-off sound (silent for the interruption listener)
        if !bargeInPending { NSSound(named: .init("Pop"))?.play() }
        bargeInPending = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        transcribedText = ""
        onListeningStopped?()
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                             didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            speakingTimeoutTask?.cancel()
            speakingTimeoutTask = nil
            isSpeaking = false
        }
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
