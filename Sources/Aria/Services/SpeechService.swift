import AVFoundation
import Speech
import SwiftUI

/// Handles both text-to-speech (reading emails aloud) and
/// speech-to-text (voice commands / dictation).
@MainActor
final class SpeechService: NSObject, ObservableObject {

    // MARK: - TTS

    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false

    func speak(_ text: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resumeSpeaking() {
        synthesizer.continueSpeaking()
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
