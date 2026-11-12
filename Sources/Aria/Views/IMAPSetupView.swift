import SwiftUI

/// Manual IMAP/SMTP credential entry — works for all providers using App Passwords.
struct IMAPSetupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let presetProvider: EmailProvider

    @State private var displayName = ""
    @State private var emailAddress = ""
    @State private var password = ""
    @State private var imapHost: String
    @State private var imapPort: String
    @State private var smtpHost: String
    @State private var smtpPort: String
    @State private var saving = false
    @State private var error: String?

    init(provider: EmailProvider = .custom) {
        self.presetProvider = provider
        let (ih, ip, sh, sp) = Self.defaultServers(for: provider)
        _imapHost = State(initialValue: ih)
        _imapPort = State(initialValue: ip)
        _smtpHost = State(initialValue: sh)
        _smtpPort = State(initialValue: sp)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                    .padding(.top, 28)
                    .accessibilityHidden(true)
                Text(presetProvider == .custom ? "Add IMAP Account" : "Sign in to \(presetProvider.rawValue)")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if let note = appPasswordNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Name + email
                    Group {
                        LabeledContent("Your name") {
                            TextField("Full name", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Email address") {
                            TextField("you@example.com", text: $emailAddress)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.emailAddress)
                        }
                        LabeledContent("Password") {
                            SecureField(presetProvider == .gmail || presetProvider == .yahoo
                                        ? "App password (16 characters)"
                                        : "Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Divider()

                    // Server settings
                    Text("Server Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Group {
                        LabeledContent("IMAP host") {
                            TextField("imap.example.com", text: $imapHost)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("IMAP port") {
                            TextField("993", text: $imapPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 80)
                        }
                        LabeledContent("SMTP host") {
                            TextField("smtp.example.com", text: $smtpHost)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("SMTP port") {
                            TextField("587", text: $smtpPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 80)
                        }
                    }

                    appPasswordGuide

                    if let error {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer buttons
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task { await save() }
                } label: {
                    if saving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add Account")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(displayName.isEmpty || emailAddress.isEmpty || password.isEmpty || saving)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Save

    private func save() async {
        saving = true
        error = nil
        guard let iport = Int(imapPort), let sport = Int(smtpPort) else {
            error = "Invalid port number."
            saving = false
            return
        }
        let account = EmailAccount(
            id: UUID(),
            displayName: displayName,
            emailAddress: emailAddress,
            provider: presetProvider,
            imapHost: imapHost,
            imapPort: iport,
            smtpHost: smtpHost,
            smtpPort: sport,
            useOAuth: false
        )
        // Save password to Keychain
        KeychainService.savePassword(password, for: account.id)
        appState.addAccount(account)
        dismiss()
    }

    // MARK: - Helpers

    private var appPasswordNote: String? {
        switch presetProvider {
        case .icloud:
            return "iCloud requires an App-Specific Password — your regular Apple ID password won't work here."
        case .gmail:
            return "Gmail requires an App Password — your regular Google password won't work here."
        case .yahoo:
            return "Yahoo requires an App Password — your regular password won't work here."
        default:
            return nil
        }
    }

    @ViewBuilder
    private var appPasswordGuide: some View {
        switch presetProvider {
        case .icloud:
            VStack(alignment: .leading, spacing: 6) {
                Text("How to create an iCloud App-Specific Password:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("1. Go to appleid.apple.com and sign in.")
                    Text("2. Under Sign-In & Security, tap App-Specific Passwords.")
                    Text("3. Tap + and name it \"Oralis\".")
                    Text("4. Copy the generated password and paste it above.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Link("Open Apple ID → App-Specific Passwords →",
                     destination: URL(string: "https://appleid.apple.com/account/manage")!)
                    .font(.caption)
            }
            .padding(12)
            .background(Color.blue.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .gmail:
            VStack(alignment: .leading, spacing: 6) {
                Text("How to create a Gmail App Password:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("1. Go to myaccount.google.com → Security.")
                    Text("2. Under \"How you sign in to Google\", tap 2-Step Verification (enable it if off).")
                    Text("3. Scroll down and tap App passwords.")
                    Text("4. Create one for Oralis and paste it above.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Link("Open Google App Passwords →",
                     destination: URL(string: "https://myaccount.google.com/apppasswords")!)
                    .font(.caption)
            }
            .padding(12)
            .background(Color.blue.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        default:
            EmptyView()
        }
    }

    private static func defaultServers(for provider: EmailProvider) -> (String, String, String, String) {
        switch provider {
        case .icloud:  return ("imap.mail.me.com",         "993", "smtp.mail.me.com",         "587")
        case .gmail:   return ("imap.gmail.com",           "993", "smtp.gmail.com",            "587")
        case .outlook: return ("outlook.office365.com",    "993", "smtp.office365.com",        "587")
        case .yahoo:   return ("imap.mail.yahoo.com",      "993", "smtp.mail.yahoo.com",       "465")
        default:       return ("",                          "993", "",                           "587")
        }
    }
}
