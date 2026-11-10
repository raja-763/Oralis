import AVFoundation
import Foundation

// MARK: - VoicePreferences

struct VoicePreferences: Codable, Equatable {
    var voiceIdentifier: String       // AVSpeechSynthesisVoice.identifier
    var rate: Float                   // 0.0 – 1.0  (AVSpeechUtteranceDefaultSpeechRate ≈ 0.5)
    var pitch: Float                  // 0.5 – 2.0
    var volume: Float                 // 0.0 – 1.0
    var autoReadNewEmails: Bool       // speak each email as you open it
    var readSenderName: Bool          // include "From: …" in read-aloud
    var readDate: Bool                // include "Received …" in read-aloud
    var announceBatchResults: Bool    // "Deleted 42 emails" etc.

    static let `default` = VoicePreferences(
        voiceIdentifier: preferredDefaultVoiceID(),
        rate: AVSpeechUtteranceDefaultSpeechRate,
        pitch: 1.0,
        volume: 1.0,
        autoReadNewEmails: false,
        readSenderName: true,
        readDate: true,
        announceBatchResults: true
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
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
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
                    return $0.quality.rawValue > $1.quality.rawValue  // premium first
                }
                return $0.name < $1.name
            }
    }
}
