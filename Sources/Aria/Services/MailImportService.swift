import Foundation
import AppKit

/// Attempts to import email accounts configured in Apple Mail via AppleScript.
/// Falls back gracefully if Mail is not installed or has no accounts.
@MainActor
final class MailImportService: ObservableObject {

    struct ImportedAccount: Identifiable {
        let id = UUID()
        let displayName: String
        let emailAddress: String
        let imapHost: String
        let imapPort: Int
        let smtpHost: String
        let smtpPort: Int
        let provider: EmailProvider
    }

    @Published var isLoading = false
    @Published var importedAccounts: [ImportedAccount] = []
    @Published var errorMessage: String?

    func fetchMailAccounts() async {
        isLoading = true
        errorMessage = nil
        importedAccounts = []

        let script = """
        tell application "Mail"
            set accountList to {}
            repeat with a in accounts
                set acType to class of a
                if acType is imap account then
                    set end of accountList to {name of a, email addresses of a, server name of a, port of a}
                end if
            end repeat
            return accountList
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            errorMessage = "Could not prepare Mail import."
            isLoading = false
            return
        }

        var errorDict: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorDict)

        if let err = errorDict {
            let msg = err["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
            if msg.contains("not running") || msg.contains("can't get") {
                errorMessage = "Apple Mail is not set up with any accounts."
            } else {
                errorMessage = "Could not access Mail: \(msg)"
            }
            isLoading = false
            return
        }

        var accounts: [ImportedAccount] = []
        let count = result.numberOfItems

        for i in 1...max(1, count) {
            guard count > 0 else { break }
            let item = result.atIndex(i)
            // Each item is a list: {name, {emails}, imapHost, imapPort}
            let name     = item?.atIndex(1)?.stringValue ?? "Mail Account"
            let emailsDesc = item?.atIndex(2)
            let email    = emailsDesc?.atIndex(1)?.stringValue ?? ""
            let imapHost = item?.atIndex(3)?.stringValue ?? ""
            let imapPort = Int(item?.atIndex(4)?.stringValue ?? "993") ?? 993

            guard !email.isEmpty, !imapHost.isEmpty else { continue }

            let provider = EmailProvider.detect(from: email, host: imapHost)
            let (smtpHost, smtpPort) = defaultSMTP(for: provider, imapHost: imapHost)

            accounts.append(ImportedAccount(
                displayName: name,
                emailAddress: email,
                imapHost: imapHost,
                imapPort: imapPort,
                smtpHost: smtpHost,
                smtpPort: smtpPort,
                provider: provider
            ))
        }

        importedAccounts = accounts
        if accounts.isEmpty {
            errorMessage = "No IMAP accounts found in Apple Mail."
        }
        isLoading = false
    }

    private func defaultSMTP(for provider: EmailProvider, imapHost: String) -> (String, Int) {
        switch provider {
        case .gmail:   return ("smtp.gmail.com", 587)
        case .outlook: return ("smtp.office365.com", 587)
        case .yahoo:   return ("smtp.mail.yahoo.com", 465)
        default:
            let smtpHost = imapHost.replacingOccurrences(of: "imap.", with: "smtp.")
            return (smtpHost, 587)
        }
    }
}

extension EmailProvider {
    static func detect(from email: String, host: String) -> EmailProvider {
        let lower = email.lowercased()
        let hostLower = host.lowercased()
        if lower.contains("gmail") || hostLower.contains("gmail") { return .gmail }
        if lower.contains("outlook") || lower.contains("hotmail") || lower.contains("live") || hostLower.contains("office365") { return .outlook }
        if lower.contains("yahoo") || hostLower.contains("yahoo") { return .yahoo }
        return .custom
    }
}
