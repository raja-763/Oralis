import AppKit
import Contacts

/// Sends text messages through the macOS Messages app.
enum TextMessageService {

    struct Recipient {
        let name: String
        let handle: String   // phone number or email address
    }

    enum Failure: LocalizedError {
        case contactsDenied
        case noMatch(String)
        case noHandle(String)
        case sendFailed(String)

        var errorDescription: String? {
            switch self {
            case .contactsDenied:
                return "Oralis is not allowed to read your contacts. Enable it in System Settings, Privacy and Security, Contacts."
            case .noMatch(let name):
                return "I could not find \(name) in your contacts. Try saying the phone number instead."
            case .noHandle(let name):
                return "\(name) has no phone number or email address in your contacts."
            case .sendFailed(let reason):
                return "Messages could not send the text. \(reason)"
            }
        }
    }

    /// Accepts a phone number, an email address, or a contact name.
    static func resolve(_ to: String) async throws -> Recipient {
        let trimmed = to.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0.isNumber }
        let looksLikeNumber = digits.count >= 7 &&
            trimmed.allSatisfy { $0.isNumber || " +-().".contains($0) }
        if looksLikeNumber {
            return Recipient(name: trimmed, handle: (trimmed.hasPrefix("+") ? "+" : "") + digits)
        }
        if trimmed.contains("@") { return Recipient(name: trimmed, handle: trimmed) }

        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else {
            throw Failure.contactsDenied
        }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
                    CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let matches = try store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: trimmed), keysToFetch: keys)
        guard let contact = matches.first else { throw Failure.noMatch(trimmed) }
        let fullName = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }.joined(separator: " ")
        let name = fullName.isEmpty ? trimmed : fullName
        let mobile = contact.phoneNumbers.first {
            ($0.label ?? "").lowercased().contains("mobile") || ($0.label ?? "").lowercased().contains("iphone")
        } ?? contact.phoneNumbers.first
        if let number = mobile?.value.stringValue {
            let d = number.filter { $0.isNumber }
            return Recipient(name: name, handle: (number.hasPrefix("+") ? "+" : "") + d)
        }
        if let email = contact.emailAddresses.first?.value as String? {
            return Recipient(name: name, handle: email)
        }
        throw Failure.noHandle(name)
    }

    @MainActor
    static func send(_ body: String, to recipient: Recipient) throws {
        // Values are passed as escaped AppleScript string literals, never as code.
        func literal(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let source = """
        tell application "Messages"
            set theHandle to \(literal(recipient.handle))
            set theBody to \(literal(body))
            try
                set theService to 1st account whose service type = iMessage
                send theBody to participant theHandle of theService
            on error
                set theService to 1st account whose service type = SMS
                send theBody to participant theHandle of theService
            end try
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error."
            throw Failure.sendFailed(message)
        }
    }
}
