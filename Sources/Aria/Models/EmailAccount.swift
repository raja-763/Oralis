import Foundation

// MARK: - Provider

enum EmailProvider: String, Codable, CaseIterable, Identifiable {
    case gmail      = "Gmail"
    case outlook    = "Outlook / Exchange"
    case icloud     = "iCloud"
    case yahoo      = "Yahoo"
    case imap       = "IMAP / SMTP"
    case custom     = "Custom"

    var id: String { rawValue }

    var supportsOAuth: Bool {
        switch self {
        case .gmail, .outlook, .icloud: return true
        default:                        return false
        }
    }

    var signInURL: URL? {
        switch self {
        case .gmail:   return URL(string: "https://myaccount.google.com/apppasswords")
        case .outlook: return URL(string: "https://account.microsoft.com/security")
        case .icloud:  return URL(string: "https://appleid.apple.com/account/manage")
        case .yahoo:   return URL(string: "https://login.yahoo.com/account/security")
        default:       return nil
        }
    }

    var oauthInstructions: String {
        switch self {
        case .gmail:
            return "Sign in with your Google account."
        case .outlook:
            return "Sign in with your Microsoft account."
        case .icloud:
            return "Sign in with your Apple ID."
        default:
            return "Enter your server details and password below."
        }
    }

    var passwordLabel: String {
        switch self {
        case .imap, .custom: return "Password"
        default:             return "App Password"
        }
    }

    var passwordHint: String {
        switch self {
        case .gmail:
            return "App Password looks like: xxxx xxxx xxxx xxxx (16 letters, spaces optional)"
        case .outlook, .icloud, .yahoo:
            return "Use an App Password, not your main account password."
        default:
            return "Your regular IMAP account password."
        }
    }

    var defaultIMAPHost: String {
        switch self {
        case .gmail:   return "imap.gmail.com"
        case .outlook: return "outlook.office365.com"
        case .icloud:  return "imap.mail.me.com"
        case .yahoo:   return "imap.mail.yahoo.com"
        default:       return ""
        }
    }

    var defaultSMTPHost: String {
        switch self {
        case .gmail:   return "smtp.gmail.com"
        case .outlook: return "smtp.office365.com"
        case .icloud:  return "smtp.mail.me.com"
        case .yahoo:   return "smtp.mail.yahoo.com"
        default:       return ""
        }
    }

    var iconName: String {
        switch self {
        case .gmail:   return "envelope.fill"
        case .outlook: return "envelope.badge.fill"
        case .icloud:  return "icloud.fill"
        case .yahoo:   return "y.circle.fill"
        default:       return "server.rack"
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
    var useOAuth: Bool

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
        useOAuth: Bool = false,
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
        self.useOAuth = useOAuth
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
