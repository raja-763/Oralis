import Foundation

/// Supplies the Google access token the public build sends to the Oralis proxy.
/// The proxy checks it with Google, so only real Oralis users with a Gmail account can
/// use the AI, and limits are counted per account. The personal build, which holds its
/// own API keys, never calls the proxy and does not use this.
enum ProxyAuth {
    private static let lock = NSLock()
    private static var accountID: UUID?
    private static var cached: String?

    /// Called whenever the selected account changes. Only Gmail accounts can authenticate.
    static func setAccount(_ id: UUID?) {
        lock.lock(); defer { lock.unlock() }
        if accountID != id { cached = nil }
        accountID = id
    }

    /// The bearer token, or nil when no Google account is signed in.
    static func token(refresh: Bool = false) async -> String? {
        lock.lock()
        let id = accountID
        let existing = cached
        lock.unlock()
        guard let id else { return nil }
        if !refresh, let existing { return existing }

        var token: String?
        if refresh {
            token = try? await OAuthService.refreshGoogleAccessToken(for: id)
        } else {
            token = KeychainService.loadAccessToken(for: id)
        }
        lock.lock(); cached = token; lock.unlock()
        return token
    }

    static let signInMessage = "To use Oralis's AI, sign in with a Google account in Settings."
}
