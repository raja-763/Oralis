import SwiftUI
import AuthenticationServices

/// Account setup — SSO sign-in for Google and Microsoft, plus Apple Mail import fallback.
struct AccountSetupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var oauth    = OAuthService()
    @StateObject private var importer = MailImportService()

    @State private var signingIn  = false
    @State private var errorMsg: String?
    @State private var showManual = false

    private static let googleConfigured    = !(Bundle.main.infoDictionary?["GOOGLE_OAUTH_CLIENT_ID"]    as? String ?? "").isEmpty
    private static let microsoftConfigured = !(Bundle.main.infoDictionary?["MICROSOFT_OAUTH_CLIENT_ID"] as? String ?? "").isEmpty

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.shield.half.filled.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                    .padding(.top, 28)
                Text("Add Email Account")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Sign in with your email provider.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    if signingIn {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.large)
                            Text("Opening sign-in page…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .accessibilityLabel("Signing in, please wait")

                    } else {
                        // ── OAuth buttons ──────────────────────────────
                        VStack(spacing: 12) {
                            if Self.googleConfigured {
                                ProviderSignInButton(
                                    label: "Sign in with Google",
                                    subtitle: "Gmail, Google Workspace",
                                    icon: "envelope.fill",
                                    tint: Color(red: 0.85, green: 0.26, blue: 0.21)
                                ) { Task { await signIn(provider: .gmail) } }
                            } else {
                                OAuthNotConfiguredRow(
                                    provider: "Google",
                                    tint: Color(red: 0.85, green: 0.26, blue: 0.21)
                                )
                            }

                            if Self.microsoftConfigured {
                                ProviderSignInButton(
                                    label: "Sign in with Microsoft",
                                    subtitle: "Outlook, Hotmail, Live",
                                    icon: "envelope.fill",
                                    tint: Color(red: 0.0, green: 0.47, blue: 0.84)
                                ) { Task { await signIn(provider: .outlook) } }
                            } else {
                                OAuthNotConfiguredRow(
                                    provider: "Microsoft",
                                    tint: Color(red: 0.0, green: 0.47, blue: 0.84)
                                )
                            }
                        }

                        if let errorMsg {
                            Text(errorMsg)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }

                        Divider()

                        // ── Apple Mail import ──────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Or import from Apple Mail")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            if importer.isLoading {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking Apple Mail…")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            } else if !importer.importedAccounts.isEmpty {
                                ForEach(importer.importedAccounts) { acc in
                                    ImportedAccountRow(account: acc) { addImported(acc) }
                                }
                            } else {
                                Text(importer.errorMessage ?? "No accounts found in Apple Mail.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            }
                        }

                        Divider()

                        // ── Manual fallback ────────────────────────────
                        Button {
                            showManual = true
                        } label: {
                            Label("Add Account Manually", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .sheet(isPresented: $showManual) {
                            IMAPSetupView(provider: .custom).environmentObject(appState)
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Credentials stored securely in macOS Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await importer.fetchMailAccounts() }
    }

    // MARK: - OAuth sign-in

    private func signIn(provider: EmailProvider) async {
        signingIn = true
        errorMsg = nil
        do {
            switch provider {
            case .gmail:
                let tokens = try await oauth.signInWithGoogle()
                let (name, email) = try await oauth.fetchGoogleUserInfo(accessToken: tokens.accessToken)
                let account = EmailAccount(id: UUID(), displayName: name, emailAddress: email,
                                           provider: .gmail, imapHost: "imap.gmail.com", imapPort: 993,
                                           smtpHost: "smtp.gmail.com", smtpPort: 587, useOAuth: true)
                KeychainService.saveOAuthTokens(tokens, for: account.id)
                appState.addAccount(account)
                dismiss()

            case .outlook:
                let tokens = try await oauth.signInWithMicrosoft()
                let (name, email) = try await oauth.fetchMicrosoftUserInfo(accessToken: tokens.accessToken)
                let account = EmailAccount(id: UUID(), displayName: name, emailAddress: email,
                                           provider: .outlook, imapHost: "outlook.office365.com", imapPort: 993,
                                           smtpHost: "smtp.office365.com", smtpPort: 587, useOAuth: true)
                KeychainService.saveOAuthTokens(tokens, for: account.id)
                appState.addAccount(account)
                dismiss()

            default: break
            }
        } catch {
            let ns = error as NSError
            if ns.domain == ASWebAuthenticationSessionErrorDomain,
               ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                // user cancelled — no message
            } else {
                errorMsg = error.localizedDescription
            }
        }
        signingIn = false
    }

    // MARK: - Apple Mail import

    private func addImported(_ imported: MailImportService.ImportedAccount) {
        let account = EmailAccount(id: UUID(), displayName: imported.displayName,
                                   emailAddress: imported.emailAddress, provider: imported.provider,
                                   imapHost: imported.imapHost, imapPort: imported.imapPort,
                                   smtpHost: imported.smtpHost, smtpPort: imported.smtpPort,
                                   useOAuth: false)
        if let pwd = AppleMailKeychain.password(for: imported.emailAddress, host: imported.imapHost) {
            KeychainService.savePassword(pwd, for: account.id)
        }
        appState.addAccount(account)
        dismiss()
    }
}

// MARK: - "Not configured" placeholder row

struct OAuthNotConfiguredRow: View {
    let provider: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: "envelope.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tint.opacity(0.4))
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sign in with \(provider)")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("Client ID not yet configured — see Settings > About")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("Sign in with \(provider) — not yet configured")
    }
}

// MARK: - ImportedAccountRow

struct ImportedAccountRow: View {
    let account: MailImportService.ImportedAccount
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: account.provider.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName).fontWeight(.medium)
                Text(account.emailAddress).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add") { onAdd() }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add \(account.emailAddress)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - AppleMailKeychain

enum AppleMailKeychain {
    static func password(for username: String, host: String) -> String? {
        var passwordLength: UInt32 = 0
        var passwordData: UnsafeMutableRawPointer?
        let status = SecKeychainFindInternetPassword(
            nil,
            UInt32(host.utf8.count), host,
            0, nil,
            UInt32(username.utf8.count), username,
            0, nil, 0,
            .any, .any,
            &passwordLength, &passwordData,
            nil
        )
        guard status == errSecSuccess, let data = passwordData else { return nil }
        let pwd = String(bytes: UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self),
            count: Int(passwordLength)
        ), encoding: .utf8)
        SecKeychainItemFreeContent(nil, passwordData)
        return pwd
    }
}

// MARK: - ProviderSignInButton

struct ProviderSignInButton: View {
    let label: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button { action() } label: {
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
                    Text(label).fontWeight(.medium).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
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
