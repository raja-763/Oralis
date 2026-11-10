import Foundation
import Security

/// Thin wrapper around the macOS Keychain for storing OAuth tokens
/// and the Anthropic API key.  All email credentials stay on-device.
final class KeychainService {
    static let shared = KeychainService()
    private let service = "com.aria.app"

    func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - OAuth helpers

    static func saveOAuthTokens(_ tokens: OAuthTokens, for accountID: UUID) {
        let keychain = KeychainService.shared
        keychain.save(key: "oauth.access.\(accountID)",  value: tokens.accessToken)
        keychain.save(key: "oauth.refresh.\(accountID)", value: tokens.refreshToken)
        keychain.save(key: "oauth.expiry.\(accountID)",  value: String(tokens.expiresAt.timeIntervalSince1970))
    }

    static func loadAccessToken(for accountID: UUID) -> String? {
        KeychainService.shared.load(key: "oauth.access.\(accountID)")
    }

    static func loadRefreshToken(for accountID: UUID) -> String? {
        KeychainService.shared.load(key: "oauth.refresh.\(accountID)")
    }

    static func savePassword(_ password: String, for accountID: UUID) {
        KeychainService.shared.save(key: "imap.password.\(accountID)", value: password)
    }

    static func loadPassword(for accountID: UUID) -> String? {
        KeychainService.shared.load(key: "imap.password.\(accountID)")
    }
}
