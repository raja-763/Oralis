import SwiftUI

/// Account setup sheet — OAuth sign-in for all providers.
struct AccountSetupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProvider: EmailProvider?

    var body: some View {
        Group {
            if let provider = selectedProvider {
                IMAPSetupView(provider: provider)
                    .environmentObject(appState)
            } else {
                providerPicker
            }
        }
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var providerPicker: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "envelope.badge.shield.half.filled.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                    .padding(.top, 32)
                Text("Add Email Account")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Choose your email provider to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
            }

            Divider().padding(.vertical, 12)

            VStack(spacing: 12) {
                ProviderSignInButton(
                    label: "Gmail",
                    subtitle: "Gmail, Google Workspace",
                    icon: "envelope.fill",
                    tint: Color(red: 0.85, green: 0.26, blue: 0.21)
                ) { selectedProvider = .gmail }

                ProviderSignInButton(
                    label: "Outlook / Hotmail",
                    subtitle: "Microsoft 365, Hotmail, Live",
                    icon: "envelope.fill",
                    tint: Color(red: 0.0, green: 0.47, blue: 0.84)
                ) { selectedProvider = .outlook }

                ProviderSignInButton(
                    label: "Yahoo Mail",
                    subtitle: "Yahoo Mail",
                    icon: "envelope.fill",
                    tint: Color(red: 0.40, green: 0.0, blue: 0.73)
                ) { selectedProvider = .yahoo }

                ProviderSignInButton(
                    label: "Other IMAP Account",
                    subtitle: "Any email with IMAP support",
                    icon: "server.rack",
                    tint: .secondary
                ) { selectedProvider = .custom }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            Divider().padding(.vertical, 8)

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
            .padding(.bottom, 20)

            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
                .accessibilityLabel("Cancel adding account")
        }
    }
}

// MARK: - Provider button

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

