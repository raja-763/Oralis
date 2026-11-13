import Foundation
import AuthenticationServices
import AppKit
import CryptoKit

/// Handles OAuth 2.0 PKCE flows for Google (Gmail) and Microsoft (Outlook).
/// No client secret is needed — public native-app clients use PKCE only.
@MainActor
final class OAuthService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Config
    // Replace these with your registered OAuth client IDs.
    // See OAUTH_SETUP.md for instructions.
    struct Config {
        static let googleClientID     = Bundle.main.infoDictionary?["GOOGLE_OAUTH_CLIENT_ID"]     as? String ?? ""
        static let googleClientSecret = Bundle.main.infoDictionary?["GOOGLE_OAUTH_CLIENT_SECRET"] as? String ?? ""
        static let microsoftClientID  = Bundle.main.infoDictionary?["MICROSOFT_OAUTH_CLIENT_ID"]  as? String ?? ""
        static let redirectScheme     = Bundle.main.infoDictionary?["OAUTH_REDIRECT_SCHEME"] as? String ?? "com.oralis.app"
    }

    // MARK: - Token refresh (called by GmailService on 401)

    static func refreshGoogleAccessToken(for accountID: UUID) async throws -> String {
        guard let refreshToken = KeychainService.loadRefreshToken(for: accountID),
              !refreshToken.isEmpty
        else { throw OralisError.notAuthenticated }

        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params: [String: String] = [
            "client_id":     Config.googleClientID,
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
        ]
        if !Config.googleClientSecret.isEmpty {
            params["client_secret"] = Config.googleClientSecret
        }
        req.httpBody = params.percentEncoded()

        var (data, response) = try await URLSession.shared.data(for: req)
        struct Err: Decodable { var error: String?; var error_description: String? }
        // Public (PKCE) clients have no secret; Google answers invalid_client if one is
        // sent that doesn't belong to the client ID. Retry once without it.
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode),
           params["client_secret"] != nil,
           (try? JSONDecoder().decode(Err.self, from: data))?.error == "invalid_client" {
            params["client_secret"] = nil
            req.httpBody = params.percentEncoded()
            (data, response) = try await URLSession.shared.data(for: req)
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let e = try? JSONDecoder().decode(Err.self, from: data)
            oralisLog("token refresh failed: \(e?.error ?? "unknown") \(e?.error_description ?? "")")
            throw OralisError.notAuthenticated
        }
        struct Resp: Decodable { var access_token: String; var expires_in: Int? }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        let expiry = Date().addingTimeInterval(TimeInterval(resp.expires_in ?? 3600))
        KeychainService.shared.save(key: "oauth.access.\(accountID)",  value: resp.access_token)
        KeychainService.shared.save(key: "oauth.expiry.\(accountID)",  value: String(expiry.timeIntervalSince1970))
        return resp.access_token
    }

    // MARK: - Google OAuth

    func signInWithGoogle() async throws -> OAuthTokens {
        let verifier = pkceVerifier()
        let challenge = pkceChallenge(for: verifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id",             value: Config.googleClientID),
            .init(name: "redirect_uri",          value: "\(Config.redirectScheme):/oauth/google"),
            .init(name: "response_type",         value: "code"),
            .init(name: "scope",                 value: "https://mail.google.com/"),
            .init(name: "code_challenge",        value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type",           value: "offline"),
            .init(name: "prompt",                value: "consent"),
        ]

        let callbackURL = try await runSession(url: components.url!, callbackScheme: Config.redirectScheme)
        let code = extractCode(from: callbackURL)

        return try await exchangeGoogle(code: code, verifier: verifier)
    }

    private func exchangeGoogle(code: String, verifier: String) async throws -> OAuthTokens {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var googleParams: [String: String] = [
            "client_id":     Config.googleClientID,
            "code":          code,
            "code_verifier": verifier,
            "grant_type":    "authorization_code",
            "redirect_uri":  "\(Config.redirectScheme):/oauth/google",
        ]
        if !Config.googleClientSecret.isEmpty {
            googleParams["client_secret"] = Config.googleClientSecret
        }
        req.httpBody = googleParams.percentEncoded()

        var (data, _) = try await URLSession.shared.data(for: req)
        struct Granted: Decodable { var error: String?; var scope: String? }
        // Same public-client rule as token refresh: retry without the secret.
        if googleParams["client_secret"] != nil,
           (try? JSONDecoder().decode(Granted.self, from: data))?.error == "invalid_client" {
            googleParams["client_secret"] = nil
            req.httpBody = googleParams.percentEncoded()
            (data, _) = try await URLSession.shared.data(for: req)
        }
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        // Google's consent page lets people leave the Gmail checkbox unticked, which
        // yields a login that can never read mail. Refuse it with a clear message.
        let granted = (try? JSONDecoder().decode(Granted.self, from: data))?.scope ?? ""
        oralisLog("google sign-in: granted scopes = [\(granted)]")
        guard granted.contains("https://mail.google.com/") else {
            throw OralisError.apiError("Google did not give Oralis permission to read your mail. Sign in again, and on Google's permission page tick the checkbox for Gmail access before pressing Continue.")
        }
        return OAuthTokens(
            provider:     .gmail,
            accessToken:  resp.access_token,
            refreshToken: resp.refresh_token ?? "",
            expiresAt:    Date().addingTimeInterval(TimeInterval(resp.expires_in ?? 3600))
        )
    }

    // MARK: - Microsoft OAuth

    func signInWithMicrosoft() async throws -> OAuthTokens {
        let verifier = pkceVerifier()
        let challenge = pkceChallenge(for: verifier)
        let tenantID  = "common"

        var components = URLComponents(string: "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/authorize")!
        components.queryItems = [
            .init(name: "client_id",             value: Config.microsoftClientID),
            .init(name: "redirect_uri",          value: "\(Config.redirectScheme):/oauth/microsoft"),
            .init(name: "response_type",         value: "code"),
            .init(name: "scope",                 value: "https://outlook.office.com/IMAP.AccessAsUser.All offline_access email openid profile"),
            .init(name: "code_challenge",        value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        let callbackURL = try await runSession(url: components.url!, callbackScheme: Config.redirectScheme)
        let code = extractCode(from: callbackURL)

        return try await exchangeMicrosoft(code: code, verifier: verifier, tenantID: tenantID)
    }

    private func exchangeMicrosoft(code: String, verifier: String, tenantID: String) async throws -> OAuthTokens {
        var req = URLRequest(url: URL(string: "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = [
            "client_id":     Config.microsoftClientID,
            "code":          code,
            "code_verifier": verifier,
            "grant_type":    "authorization_code",
            "redirect_uri":  "\(Config.redirectScheme):/oauth/microsoft",
            "scope":         "https://outlook.office.com/IMAP.AccessAsUser.All offline_access email openid profile",
        ].percentEncoded()

        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthTokens(
            provider:     .outlook,
            accessToken:  resp.access_token,
            refreshToken: resp.refresh_token ?? "",
            expiresAt:    Date().addingTimeInterval(TimeInterval(resp.expires_in ?? 3600))
        )
    }

    // MARK: - Fetch user info after sign-in

    func fetchGoogleUserInfo(accessToken: String) async throws -> (name: String, email: String) {
        // Only the Gmail scope is requested (asking for several makes Google show a
        // checkbox list that is easy to miss), so the address comes from Gmail itself.
        var req = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Info: Decodable { var emailAddress: String }
        let info = try JSONDecoder().decode(Info.self, from: data)
        let name = info.emailAddress.split(separator: "@").first.map(String.init) ?? info.emailAddress
        return (name, info.emailAddress)
    }

    func fetchMicrosoftUserInfo(accessToken: String) async throws -> (name: String, email: String) {
        var req = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Info: Decodable { var displayName: String; var mail: String? ; var userPrincipalName: String }
        let info = try JSONDecoder().decode(Info.self, from: data)
        return (info.displayName, info.mail ?? info.userPrincipalName)
    }

    // MARK: - ASWebAuthenticationSession

    private func runSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: OAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }

    // MARK: - PKCE helpers

    private func pkceVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func pkceChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    private func extractCode(from url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value ?? ""
    }
}

// MARK: - Supporting types

struct OAuthTokens {
    var provider: EmailProvider
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum OAuthError: LocalizedError {
    case cancelled
    var errorDescription: String? {
        switch self { case .cancelled: return "Sign-in was cancelled." }
    }
}

private struct TokenResponse: Decodable {
    var access_token: String
    var refresh_token: String?
    var expires_in: Int?
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension [String: String] {
    func percentEncoded() -> Data? {
        map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
    }
}
