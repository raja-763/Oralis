import Foundation

// MARK: - Provider

enum EmailProvider: String, Codable, CaseIterable, Identifiable {
    case gmail      = "Gmail"
    case outlook    = "Outlook / Exchange"
    case icloud     = "iCloud"
    case yahoo      = "Yahoo"
    case imap       = "IMAP / SMTP"

    var id: String { rawValue }

    var supportsOAuth: Bool {
        switch self {
        case .gmail, .outlook, .icloud: return true
        case .yahoo, .imap:             return false
        }
    }

    var iconName: String {
        switch self {
        case .gmail:   return "envelope.fill"
        case .outlook: return "envelope.badge.fill"
        case .icloud:  return "icloud.fill"
        case .yahoo:   return "y.circle.fill"
        case .imap:    return "server.rack"
        }
    }
}

// MARK: - EmailAccount

struct EmailAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var emailAddress: String
    var provider: EmailProvider

    // IMAP/SMTP fields (only used for .imap provider)
    var imapHost: String
    var imapPort: Int
    var smtpHost: String
    var smtpPort: Int
    var useSSL: Bool

    // OAuth credential reference stored in Keychain (not serialised here)
    var keychainToken: String   // key used to retrieve token from Keychain

    // macOS Mail import flag
    var importedFromMailApp: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        emailAddress: String,
        provider: EmailProvider,
        imapHost: String = "",
        imapPort: Int = 993,
        smtpHost: String = "",
        smtpPort: Int = 587,
        useSSL: Bool = true,
        keychainToken: String = "",
        importedFromMailApp: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.provider = provider
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.useSSL = useSSL
        self.keychainToken = keychainToken
        self.importedFromMailApp = importedFromMailApp
    }

    /// Accessibility label read by VoiceOver in account lists.
    var accessibilityLabel: String {
        "\(displayName), \(emailAddress), \(provider.rawValue)"
    }
}

// MARK: - AccountStore (persists to UserDefaults; tokens stay in Keychain)

final class AccountStore {
    static let shared = AccountStore()
    private let key = "oralis.accounts"

    func loadAll() -> [EmailAccount] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([EmailAccount].self, from: data)
        else { return [] }
        return decoded
    }

    func save(_ accounts: [EmailAccount]) {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
