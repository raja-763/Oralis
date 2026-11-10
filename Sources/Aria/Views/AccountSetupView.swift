import SwiftUI
import AuthenticationServices

/// Account setup sheet — OAuth sign-in for all providers.
struct AccountSetupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var oauth = OAuthService()

    @State private var signingIn = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            VStack(spacing: 10) {
                Image(systemName: "envelope.badge.shield.half.filled.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                    .padding(.top, 32)

                Text("Add Email Account")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                Text("Sign in securely — Oralis never stores your password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
            }

            Divider().padding(.vertical, 12)

            // ── Provider buttons ────────────────────────────────────────
            if signingIn {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel("Signing in, please wait")
                    Text("Opening sign-in page…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    ProviderSignInButton(
                        label: "Sign in with Google",
                        subtitle: "Gmail, Google Workspace",
                        icon: "envelope.fill",
                        tint: Color(red: 0.85, green: 0.26, blue: 0.21)
                    ) { await signIn(provider: .gmail) }

                    ProviderSignInButton(
                        label: "Sign in with Microsoft",
                        subtitle: "Outlook, Hotmail, Live",
                        icon: "envelope.fill",
                        tint: Color(red: 0.0, green: 0.47, blue: 0.84)
                    ) { await signIn(provider: .outlook) }

                    ProviderSignInButton(
                        label: "Sign in with Yahoo",
                        subtitle: "Yahoo Mail",
                        icon: "envelope.fill",
                        tint: Color(red: 0.40, green: 0.0, blue: 0.73)
                    ) { await signIn(provider: .yahoo) }

                    ProviderSignInButton(
                        label: "Other IMAP Account",
                        subtitle: "Any email with IMAP support",
                        icon: "server.rack",
                        tint: .secondary
                    ) { await signIn(provider: .custom) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            Divider().padding(.vertical, 8)

            // ── Footer ──────────────────────────────────────────────────
            HStack {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Credentials stored securely in macOS Keychain. Never sent to Oralis servers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
                .accessibilityLabel("Cancel adding account")
        }
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sign-in

    private func signIn(provider: EmailProvider) async {
        signingIn = true
        error = nil
        do {
            switch provider {
            case .gmail:
                guard !OAuthService.Config.googleClientID.isEmpty else {
                    throw OAuthSetupError.missingClientID("Google")
                }
                let tokens = try await oauth.signInWithGoogle()
                let (name, email) = try await oauth.fetchGoogleUserInfo(accessToken: tokens.accessToken)
                let account = EmailAccount(
                    id: UUID(),
                    displayName: name,
                    emailAddress: email,
                    provider: .gmail,
                    imapHost: "imap.gmail.com",
                    imapPort: 993,
                    smtpHost: "smtp.gmail.com",
                    smtpPort: 587,
                    useOAuth: true
                )
                KeychainService.saveOAuthTokens(tokens, for: account.id)
                appState.addAccount(account)
                dismiss()

            case .outlook:
                guard !OAuthService.Config.microsoftClientID.isEmpty else {
                    throw OAuthSetupError.missingClientID("Microsoft")
                }
                let tokens = try await oauth.signInWithMicrosoft()
                let (name, email) = try await oauth.fetchMicrosoftUserInfo(accessToken: tokens.accessToken)
                let account = EmailAccount(
                    id: UUID(),
                    displayName: name,
                    emailAddress: email,
                    provider: .outlook,
                    imapHost: "outlook.office365.com",
                    imapPort: 993,
                    smtpHost: "smtp.office365.com",
                    smtpPort: 587,
                    useOAuth: true
                )
                KeychainService.saveOAuthTokens(tokens, for: account.id)
                appState.addAccount(account)
                dismiss()

            default:
                // For Yahoo and custom IMAP, fall back to manual entry
                appState.showIMAPSetup = true
                dismiss()
            }
        } catch OAuthSetupError.missingClientID(let provider) {
            error = "\(provider) sign-in is not configured yet. See Settings > About for setup instructions."
        } catch {
            if (error as NSError).domain == ASWebAuthenticationSessionErrorDomain,
               (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                // User cancelled — no error shown
            } else {
                self.error = error.localizedDescription
            }
        }
        signingIn = false
    }
}

// MARK: - Provider button

struct ProviderSignInButton: View {
    let label: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tint.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(tint)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label). \(subtitle)")
    }
}

// MARK: - Errors

enum OAuthSetupError: LocalizedError {
    case missingClientID(String)
    var errorDescription: String? {
        switch self {
        case .missingClientID(let p): return "\(p) client ID not configured."
        }
    }
}
