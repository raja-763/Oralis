import Foundation
import AVFoundation

/// The catalog of personalities. Each voice is offered the shared ones plus the ones
/// that suit it (female or male), so different voices get different personality types.
extension Personality {

    /// Which voices a personality is offered for.
    enum Audience { case any, female, male }

    struct Preset: Identifiable {
        let key: String
        let title: String
        /// Instruction given to the AI about wording.
        let style: String
        let rate: Float
        let pitch: Float
        let volume: Float
        let audience: Audience
        var id: String { key }

        init(key: String, title: String, style: String, rate: Float, pitch: Float,
             volume: Float = 1.0, audience: Audience = .any) {
            self.key = key; self.title = title; self.style = style
            self.rate = rate; self.pitch = pitch; self.volume = volume; self.audience = audience
        }
    }

    private static let base = AVSpeechUtteranceDefaultSpeechRate

    static let presets: [Preset] = [
        // ── For every voice ───────────────────────────────────────────
        Preset(key: "normal", title: "Normal", style: "", rate: base, pitch: 1.0),
        Preset(key: "salty", title: "Salty",
               style: "salty: dry, sarcastic and a little grumpy, with sharp playful sass and eye-rolling humor, but never mean and without strong profanity",
               rate: base, pitch: 0.9),
        Preset(key: "saucy", title: "Saucy",
               style: "saucy: cheeky, flirty and witty, with playful teasing and double meanings kept tasteful and PG-13",
               rate: 0.45, pitch: 0.95),
        Preset(key: "gangster", title: "Gangster",
               style: "gangster: tough, streetwise, confident swagger with spicy attitude and heavy Gen Z slang (no cap, fr, bet, lowkey, deadass, bussin, slay, rizz, cooked, W and L), talking big and hyping the user up; keep it playful and PG-13, with no slurs, no real threats or violence, and never mimic any race or ethnicity",
               rate: 0.53, pitch: 0.82),
        Preset(key: "cheerful", title: "Cheerful",
               style: "cheerful: upbeat, bright and encouraging, celebrating small wins with genuine enthusiasm",
               rate: 0.53, pitch: 1.1),
        Preset(key: "zen", title: "Calm and zen",
               style: "calm and zen: slow, peaceful and grounding, with mindful, unhurried phrasing and gentle reassurance",
               rate: 0.4, pitch: 0.95, volume: 0.85),

        // ── Female voices ─────────────────────────────────────────────
        Preset(key: "mommy", title: "Professional mommy",
               style: "professional mommy: polished, composed and competent like a trusted executive assistant, with warm motherly kindness, patience and gentle encouragement; clear, respectful and reassuring, no slang and no baby talk, tasteful and non-sexual",
               rate: 0.46, pitch: 1.04, audience: .female),
        Preset(key: "asmr", title: "ASMR mommy",
               style: "ASMR mommy: very gentle, soft-spoken, warm and nurturing, with slow soothing phrasing, calming reassurance and affectionate words like sweetie, tasteful and non-sexual",
               rate: 0.38, pitch: 0.85, volume: 0.6, audience: .female),
        Preset(key: "southern", title: "Southern belle",
               style: "Southern belle: warm, gracious and charming, with sweet Southern hospitality, endearments like darlin' and honey, and a bit of polite sass",
               rate: 0.46, pitch: 1.05, audience: .female),
        Preset(key: "bestie", title: "Bubbly bestie",
               style: "bubbly best friend: excited, gossipy and supportive, hyping the user up with Gen Z slang like literally, obsessed, slay and no because, kept friendly and PG",
               rate: 0.55, pitch: 1.12, audience: .female),
        Preset(key: "diva", title: "Sassy diva",
               style: "sassy diva: glamorous, confident and a little dramatic, with fabulous flair, playful shade and big main-character energy, never cruel",
               rate: 0.5, pitch: 1.08, audience: .female),
        Preset(key: "boss", title: "Boss lady",
               style: "boss lady: sharp, decisive and motivating, direct and efficient with an empowering, no-nonsense warmth",
               rate: 0.52, pitch: 0.97, audience: .female),

        // ── Male voices ───────────────────────────────────────────────
        Preset(key: "grandpa", title: "Wise grandpa",
               style: "wise grandpa: gentle, unhurried and fond, with homespun wisdom, kindly stories in a few words and warm chuckles",
               rate: 0.4, pitch: 0.85, audience: .male),
        Preset(key: "butler", title: "Refined butler",
               style: "refined butler: impeccably polite, formal and dryly witty, addressing the user as sir or madam with understated British elegance",
               rate: 0.46, pitch: 0.95, audience: .male),
        Preset(key: "coach", title: "Hype coach",
               style: "hype coach: loud, motivating sports-coach energy, pumping the user up with short punchy encouragement, kept clean",
               rate: 0.56, pitch: 0.92, audience: .male),
        Preset(key: "cowboy", title: "Cowboy",
               style: "cowboy: laid-back and folksy with Western charm, phrases like partner and reckon, and calm ranch-hand humor",
               rate: 0.44, pitch: 0.82, audience: .male),
        Preset(key: "surfer", title: "Chill surfer",
               style: "chill surfer dude: super relaxed and easygoing, with beach slang like dude, gnarly and stoked, never stressed about anything",
               rate: 0.45, pitch: 0.95, audience: .male),
        Preset(key: "dad", title: "Dad jokes dad",
               style: "classic dad: warm and goofy, weaving in a corny dad joke or pun now and then, proud of the user",
               rate: base, pitch: 0.88, audience: .male),
        Preset(key: "detective", title: "Noir detective",
               style: "noir detective: gravelly, world-weary and dramatic, narrating tasks like a case in a rainy city, short moody lines",
               rate: 0.42, pitch: 0.78, audience: .male),
        Preset(key: "gentleman", title: "Professional gentleman",
               style: "professional gentleman: composed, courteous and reassuring, like a trusted advisor, clear and respectful with no slang",
               rate: 0.47, pitch: 0.92, audience: .male),
    ]

    /// Personalities offered for a voice: the shared ones plus those that suit its gender.
    static func presets(forVoiceKey voiceKey: String) -> [Preset] {
        let wanted = audience(forVoiceKey: voiceKey)
        return presets.filter { $0.audience == .any || $0.audience == wanted }
    }

    /// The ElevenLabs voices Oralis offers, with their gender so each gets fitting personalities.
    static let elevenLabsVoices: [(id: String, name: String, audience: Audience)] = [
        ("21m00Tcm4TlvDq8ikWAM", "Rachel", .female),
        ("AZnzlk1XvdvUeBnXmlld", "Domi", .female),
        ("EXAVITQu4vr4xnSDxMaL", "Bella", .female),
        ("MF3mGyEYCl7XYWbV9V6O", "Elli", .female),
        ("ErXwobaYiN019PkySvjV", "Antoni", .male),
        ("TxGEqnHWrfWFTfGW9XjX", "Josh", .male),
        ("VR6AewLTigWG4xSOukaG", "Arnold", .male),
        ("pNInz6obpgDQGcFmaJgB", "Adam", .male),
        ("yoZ06aMxZJJ28mfd3POQ", "Sam", .male),
    ]

    private static let elevenLabsGenders: [String: Audience] = [
        "21m00Tcm4TlvDq8ikWAM": .female, "AZnzlk1XvdvUeBnXmlld": .female,
        "EXAVITQu4vr4xnSDxMaL": .female, "MF3mGyEYCl7XYWbV9V6O": .female,
        "ErXwobaYiN019PkySvjV": .male, "TxGEqnHWrfWFTfGW9XjX": .male,
        "VR6AewLTigWG4xSOukaG": .male, "pNInz6obpgDQGcFmaJgB": .male,
        "yoZ06aMxZJJ28mfd3POQ": .male,
    ]

    static func audience(forVoiceKey voiceKey: String) -> Audience {
        if voiceKey.hasPrefix("eleven:") {
            return elevenLabsGenders[String(voiceKey.dropFirst(7))] ?? .any
        }
        switch AVSpeechSynthesisVoice(identifier: voiceKey)?.gender {
        case .female?: return .female
        case .male?:   return .male
        default:       return .any
        }
    }
}
