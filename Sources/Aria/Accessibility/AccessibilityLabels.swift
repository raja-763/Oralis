import SwiftUI

/// Centralised accessibility string constants.
/// Every user-facing string goes through here so changes propagate everywhere.
enum A11y {

    enum Toolbar {
        static let openAgent  = "Open AI email assistant"
        static let closeAgent = "Close AI email assistant"
        static let refresh    = "Refresh inbox"
        static let compose    = "Compose new email"
        static let readAloud  = "Read current email aloud"
        static let stopRead   = "Stop reading"
    }

    enum EmailList {
        static func threadLabel(_ thread: EmailThread) -> String {
            thread.accessibilityLabel
        }
        static let empty      = "Inbox is empty."
        static let loading    = "Loading emails."
    }

    enum Agent {
        static let openMic    = "Start voice input"
        static let closeMic   = "Stop voice input"
        static let send       = "Send message to Aria"
        static let inputHint  = "Type a message or press the microphone button to speak"
        static let thinking   = "Aria is thinking"
    }

    enum Compose {
        static let toField      = "To: recipient email address"
        static let ccField      = "CC: optional additional recipients"
        static let subjectField = "Subject"
        static let bodyField    = "Message body"
        static let send         = "Send email"
        static let cancel       = "Cancel compose"
    }

    enum AccountSetup {
        static let title   = "Add a new email account"
        static func importLabel(_ count: Int) -> String {
            "Import \(count) account\(count == 1 ? "" : "s") found in macOS Mail"
        }
    }

    enum Batch {
        static func selected(_ n: Int) -> String { "\(n) email\(n == 1 ? "" : "s") selected" }
        static func delete(_ n: Int)   -> String { "Delete \(n) email\(n == 1 ? "" : "s")" }
        static func archive(_ n: Int)  -> String { "Archive \(n) email\(n == 1 ? "" : "s")" }
        static func markRead(_ n: Int) -> String { "Mark \(n) email\(n == 1 ? "" : "s") as read" }
    }
}

// MARK: - View modifier for consistent accessible focus rings

struct AccessibleFocusRing: ViewModifier {
    func body(content: Content) -> some View {
        content
            .focusEffectDisabled(false)
    }
}

extension View {
    func accessibleFocusRing() -> some View {
        modifier(AccessibleFocusRing())
    }
}
