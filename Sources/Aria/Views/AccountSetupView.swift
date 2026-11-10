import SwiftUI

/// Account setup — primary path is importing from Apple Mail.
/// Falls back to manual IMAP entry for accounts not in Mail.
struct AccountSetupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importer = MailImportService()

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
                Text("Oralis can import accounts already set up in Apple Mail.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // ── Import from Apple Mail ───────────────────────────
                    if importer.isLoading {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Reading Apple Mail accounts…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .accessibilityLabel("Loading Apple Mail accounts")

                    } else if !importer.importedAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Found in Apple Mail")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(importer.importedAccounts) { acc in
                                ImportedAccountRow(account: acc) {
                                    addImported(acc)
                                }
                            }
                        }

                        Divider()

                        manualFallbackButton

                    } else {
                        // No Mail accounts or error
                        VStack(spacing: 16) {
                            Image(systemName: "envelope.slash")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)

                            if let err = importer.errorMessage {
                                Text(err)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }

                            Button {
                                Task { await importer.fetchMailAccounts() }
                            } label: {
                                Label("Try Again", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)

                            Divider()

                            manualFallbackButton
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Credentials stored securely in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
                .accessibilityLabel("Cancel adding account")
        }
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await importer.fetchMailAccounts() }
    }

    // MARK: - Manual fallback

    @State private var showManual = false

    private var manualFallbackButton: some View {
        VStack(spacing: 8) {
            Text("Not using Apple Mail?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Button {
                showManual = true
            } label: {
                Label("Add Account Manually", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showManual) {
                IMAPSetupView(provider: .custom)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Add imported account

    private func addImported(_ imported: MailImportService.ImportedAccount) {
        let account = EmailAccount(
            id: UUID(),
            displayName: imported.displayName,
            emailAddress: imported.emailAddress,
            provider: imported.provider,
            imapHost: imported.imapHost,
            imapPort: imported.imapPort,
            smtpHost: imported.smtpHost,
            smtpPort: imported.smtpPort,
            useOAuth: false
        )
        // Try to load the password Apple Mail already stored in Keychain
        if let pwd = AppleMailKeychain.password(for: imported.emailAddress, host: imported.imapHost) {
            KeychainService.savePassword(pwd, for: account.id)
        }
        appState.addAccount(account)
        dismiss()
    }
}

// MARK: - Row for an imported account

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

// MARK: - ProviderSignInButton (kept for OnboardingView)

struct ProviderSignInButton: View {
    let label: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            action()
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
                    Text(label).fontWeight(.medium).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
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

// MARK: - Try to read Apple Mail's Keychain entry for an account

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

        guard status == errSecSuccess,
              let data = passwordData else { return nil }

        let pwd = String(bytes: UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self),
            count: Int(passwordLength)
        ), encoding: .utf8)

        SecKeychainItemFreeContent(nil, passwordData)
        return pwd
    }
}
