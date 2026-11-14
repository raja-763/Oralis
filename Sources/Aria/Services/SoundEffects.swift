import AppKit

/// Short confirmation sounds played after an action has actually succeeded.
enum SoundEffects {
    /// Played once an email has been deleted (moved to the trash).
    static func deleted() { play("Funk") }
    /// Played once an email has been sent.
    static func sent() { play("Hero") }

    /// Played when a conversation ends, in place of any spoken goodbye.
    static func conversationEnded() { play("Submarine") }

    private static func play(_ name: String) {
        // A copy lets the sound overlap with other tones instead of being skipped
        // while the shared instance is still playing.
        let sound = NSSound(named: .init(name))?.copy() as? NSSound
        sound?.play()
    }
}
