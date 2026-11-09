import Foundation

/// Reads account information from macOS Mail's configuration so users
/// don't have to re-enter credentials they've already set up.
/// Only runs with explicit user consent (shown in onboarding sheet).
struct MacMailImporter {

    struct MailAccountConfig {
        var displayName: String
        var emailAddress: String
        var provider: EmailProvider
        var imapHost: String
        var imapPort: Int
        var smtpHost: String
        var smtpPort: Int
    }

    /// Reads ~/Library/Mail/V10/MailData/Accounts.plist (or equivalent).
    /// Returns an empty array if permission is denied or the file doesn't exist.
    static func importAccounts() -> [MailAccountConfig] {
        let paths: [String] = [
            "Library/Mail/V10/MailData/Accounts.plist",
            "Library/Mail/V9/MailData/Accounts.plist",
            "Library/Containers/com.apple.mail/Data/Library/Mail/V10/MailData/Accounts.plist"
        ]

        for rel in paths {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(rel)
            if let configs = parse(url: url), !configs.isEmpty {
                return configs
            }
        }
        return []
    }

    private static func parse(url: URL) -> [MailAccountConfig]? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any],
              let accountsArr = root["MailAccounts"] as? [[String: Any]]
        else { return nil }

        return accountsArr.compactMap { dict -> MailAccountConfig? in
            guard let email = dict["EmailAddresses"] as? [String], let addr = email.first
            else { return nil }

            let name = dict["FullUserName"] as? String ?? addr
            let imapHost = dict["Hostname"] as? String ?? ""
            let imapPort = dict["PortNumber"] as? Int ?? 993
            let smtpHost = (dict["SMTPServer"] as? [String: Any])?["Hostname"] as? String ?? ""
            let smtpPort = (dict["SMTPServer"] as? [String: Any])?["PortNumber"] as? Int ?? 587

            let provider: EmailProvider
            if imapHost.contains("gmail") || imapHost.contains("google") { provider = .gmail }
            else if imapHost.contains("outlook") || imapHost.contains("office365") || imapHost.contains("microsoft") { provider = .outlook }
            else if imapHost.contains("icloud") || imapHost.contains("me.com") { provider = .icloud }
            else if imapHost.contains("yahoo") { provider = .yahoo }
            else { provider = .imap }

            return MailAccountConfig(
                displayName: name,
                emailAddress: addr,
                provider: provider,
                imapHost: imapHost,
                imapPort: imapPort,
                smtpHost: smtpHost,
                smtpPort: smtpPort
            )
        }
    }
}
