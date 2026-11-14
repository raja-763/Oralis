import Foundation
import AVFoundation

/// How Oralis talks: a style for its wording, plus a matching delivery (pace, pitch,
/// softness) applied to whichever voice is in use. The voice itself is never changed.
enum Personality {
    struct Preset: Identifiable {
        let key: String
        let title: String
        /// Instruction given to the AI about wording.
        let style: String
        let rate: Float
        let pitch: Float
        let volume: Float
        var id: String { key }
    }

    static let presets: [Preset] = [
        Preset(key: "normal", title: "Normal", style: "",
               rate: AVSpeechUtteranceDefaultSpeechRate, pitch: 1.0, volume: 1.0),
        Preset(key: "salty", title: "Salty",
               style: "salty: dry, sarcastic and a little grumpy, with sharp playful sass and eye-rolling humor, but never mean and without strong profanity",
               rate: AVSpeechUtteranceDefaultSpeechRate, pitch: 0.9, volume: 1.0),
        Preset(key: "saucy", title: "Saucy",
               style: "saucy: cheeky, flirty and witty, with playful teasing and double meanings kept tasteful and PG-13",
               rate: 0.45, pitch: 0.95, volume: 1.0),
        Preset(key: "gangster", title: "Gangster",
               style: "gangster: tough, streetwise, confident swagger with spicy attitude and heavy Gen Z slang (no cap, fr, bet, lowkey, deadass, bussin, slay, rizz, cooked, W and L), talking big and hyping the user up; keep it playful and PG-13, with no slurs, no real threats or violence, and never mimic any race or ethnicity",
               rate: 0.53, pitch: 0.82, volume: 1.0),
        Preset(key: "asmr", title: "ASMR mommy",
               style: "ASMR mommy: very gentle, soft-spoken, warm and nurturing, with slow soothing phrasing, calming reassurance and affectionate words like sweetie, tasteful and non-sexual",
               rate: 0.38, pitch: 0.85, volume: 0.6),
    ]

    private static let key = "oralis.persona"
    private static let presetKey = "oralis.personaPreset"

    /// The wording style, empty for normal.
    static var style: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(String(newValue.prefix(200)), forKey: key) }
    }

    /// Which preset is active in Settings ("custom" for a style the user described).
    static var presetKey_: String {
        get { UserDefaults.standard.string(forKey: presetKey) ?? "normal" }
        set { UserDefaults.standard.set(newValue, forKey: presetKey) }
    }

    static func preset(matching text: String) -> Preset? {
        let t = text.lowercased()
        guard !t.isEmpty else { return nil }
        return presets.first { t == $0.key || t == $0.title.lowercased() }
            ?? presets.first { $0.key != "normal" && t.contains($0.key) }
    }

    /// Applies a preset's wording and delivery to the given preferences.
    static func apply(_ preset: Preset, to prefs: inout VoicePreferences) {
        style = preset.style
        presetKey_ = preset.key
        prefs.rate = preset.rate
        prefs.pitch = preset.pitch
        prefs.volume = preset.volume
    }

    /// Added to the AI's instructions. Empty when no personality is set.
    static var promptBlock: String {
        let s = style
        guard !s.isEmpty else { return "" }
        return """


        PERSONALITY: The user asked you to speak in this style: \(s).
        Use it for your own spoken replies and confirmations. Never write stage directions, asterisks or emoji; everything you write is read aloud. Stay accurate and brief, keep every action JSON block exactly correct, and never change the wording of emails you draft or read for the user unless they ask. Keep it tasteful: no explicit sexual content and nothing hurtful. If they ask for normal again, drop the style.
        """
    }
}
