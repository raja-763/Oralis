import AVFoundation
import Foundation

// MARK: - VoicePreferences

/// Order in which email fields are read aloud.
enum EmailReadOrder: String, Codable, CaseIterable, Identifiable {
    case senderSubjectDateBody = "Sender, Subject, Date, Body"
    case subjectSenderDateBody = "Subject, Sender, Date, Body"
    case subjectDateSenderBody = "Subject, Date, Sender, Body"
    case bodyOnly              = "Body only"
    case summaryOnly           = "Summary only (AI)"
    var id: String { rawValue }
}

/// How much of a response Oralis speaks.
enum ResponseLength: String, Codable, CaseIterable, Identifiable {
    case short  = "Short (key points)"
    case full   = "Full response"
    var id: String { rawValue }
}

struct VoicePreferences: Codable, Equatable {
    var voiceIdentifier: String       // AVSpeechSynthesisVoice.identifier
    var rate: Float                   // 0.0 – 1.0
    var pitch: Float                  // 0.5 – 2.0
    var volume: Float                 // 0.0 – 1.0
    var autoReadNewEmails: Bool
    var readSenderName: Bool
    var readDate: Bool
    var announceBatchResults: Bool
    // ElevenLabs — only used when proxy URL is configured
    var useElevenLabs: Bool           = false
    var elevenLabsVoiceID: String     = ""
    // Language for both STT (SFSpeechRecognizer) and Apple TTS voice selection
    var language: String              = "en-US"
    // Reading customisation
    var emailReadOrder: EmailReadOrder = .senderSubjectDateBody
    var responseLength: ResponseLength = .full
    var readEmailSummaryOnly: Bool     = false

    static let `default` = VoicePreferences(
        voiceIdentifier: preferredDefaultVoiceID(),
        rate: AVSpeechUtteranceDefaultSpeechRate,
        pitch: 1.0,
        volume: 1.0,
        autoReadNewEmails: false,
        readSenderName: true,
        readDate: true,
        announceBatchResults: true,
        useElevenLabs: false,
        elevenLabsVoiceID: "",
        language: "en-US",
        emailReadOrder: .senderSubjectDateBody,
        responseLength: .full,
        readEmailSummaryOnly: false
    )

    // Pick the highest-quality English voice available.
    private static func preferredDefaultVoiceID() -> String {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        let premium = voices.filter { $0.quality == .premium }
        let enhanced = voices.filter { $0.quality == .enhanced }
        return (premium.first ?? enhanced.first ?? voices.first)?.identifier
            ?? AVSpeechSynthesisVoice(language: "en-US")!.identifier
    }
}

// MARK: - VoicePreferencesStore

final class VoicePreferencesStore {
    static let shared = VoicePreferencesStore()
    private let key = "oralis.voicePreferences"

    var current: VoicePreferences {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let prefs = try? JSONDecoder().decode(VoicePreferences.self, from: data)
            else { return .default }
            return prefs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}

// MARK: - OralisVoice  (wrapper for display in UI)

struct OralisVoice: Identifiable, Equatable {
    let id: String               // AVSpeechSynthesisVoice.identifier
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality
    let gender: String           // derived from identifier heuristic

    var qualityLabel: String {
        switch quality {
        case .premium:  return "Premium"
        case .enhanced: return "Enhanced"
        default:        return "Standard"
        }
    }

    var qualityBadgeColor: String {   // used in SwiftUI as Color name
        switch quality {
        case .premium:  return "yellow"
        case .enhanced: return "blue"
        default:        return "gray"
        }
    }

    var avVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: id)
    }

    static func allEnglishVoices() -> [OralisVoice] {
        allVoices(for: "en-US")
    }

    static func allVoices(for locale: String = "en-US") -> [OralisVoice] {
        let prefix = locale.split(separator: "-").first.map(String.init) ?? locale
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .map { v in
                OralisVoice(
                    id: v.identifier,
                    name: v.name,
                    language: Locale(identifier: v.language).localizedString(forLanguageCode: v.language) ?? v.language,
                    quality: v.quality,
                    gender: v.identifier.lowercased().contains("male") ? "Male" : "Female"
                )
            }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
                return $0.name < $1.name
            }
    }
}
