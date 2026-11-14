import Foundation
import AVFoundation

/// How Oralis talks: a style for its wording, plus a matching delivery (pace, pitch,
/// softness) applied to whichever voice is in use. The voice itself is never changed.
enum Personality {
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
        if let exact = presets.first(where: { t == $0.key || t == $0.title.lowercased() }) { return exact }
        // A phrase like "soft ASMR mommy": the longest matching title wins, then any key.
        let byTitle = presets.filter { $0.key != "normal" && t.contains($0.title.lowercased()) }
            .max { $0.title.count < $1.title.count }
        return byTitle ?? presets.first { $0.key != "normal" && t.contains($0.key) }
    }

    // MARK: - Per-voice personalities

    /// Each voice remembers its own personality. Keyed by the Apple voice identifier,
    /// or "eleven:<id>" for an ElevenLabs voice.
    private static let perVoiceKey = "oralis.personaByVoice"

    static func voiceKey(for prefs: VoicePreferences) -> String {
        prefs.useElevenLabs && !prefs.elevenLabsVoiceID.isEmpty
            ? "eleven:\(prefs.elevenLabsVoiceID)" : prefs.voiceIdentifier
    }

    private static var perVoice: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: perVoiceKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: perVoiceKey) }
    }

    /// A preset key, or "custom:<style>"; nil if this voice has none yet.
    static func stored(forVoice key: String) -> String? { perVoice[key] }

    static func store(_ value: String, forVoice key: String) {
        var all = perVoice
        all[key] = value
        perVoice = all
    }

    /// The personality now in effect, in storable form.
    private static var currentValue: String {
        presetKey_ == "custom" ? "custom:" + style : presetKey_
    }

    private static func applyPreset(_ preset: Preset, to prefs: inout VoicePreferences) {
        style = preset.style
        presetKey_ = preset.key
        prefs.rate = preset.rate
        prefs.pitch = preset.pitch
        prefs.volume = preset.volume
    }

    /// Makes `value` (a preset key or "custom:<style>") the active personality.
    static func activate(_ value: String, to prefs: inout VoicePreferences) {
        if value.hasPrefix("custom:") {
            style = String(value.dropFirst(7))
            presetKey_ = "custom"
        } else if let preset = presets.first(where: { $0.key == value }) {
            applyPreset(preset, to: &prefs)
        }
    }

    /// Applies a preset to the current voice and remembers it for that voice.
    static func apply(_ preset: Preset, to prefs: inout VoicePreferences) {
        applyPreset(preset, to: &prefs)
        store(preset.key, forVoice: voiceKey(for: prefs))
    }

    /// Applies a free-form style to the current voice and remembers it for that voice.
    static func setCustom(_ text: String, for prefs: VoicePreferences) {
        style = text
        presetKey_ = "custom"
        store("custom:" + style, forVoice: voiceKey(for: prefs))
    }

    /// Call after the voice changes: the new voice brings back its own personality.
    /// A voice with none yet keeps the current one, and remembers it.
    static func restore(for prefs: inout VoicePreferences) {
        let key = voiceKey(for: prefs)
        if let value = stored(forVoice: key) {
            activate(value, to: &prefs)
        } else {
            store(currentValue, forVoice: key)
        }
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
