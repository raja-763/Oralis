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

                    if let appLink = appPasswordLink {
                        Link("How to create an App Password →", destination: URL(string: appLink)!)
                            .font(.caption)
                    }

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
        case .gmail:
            return "Gmail requires an App Password — your regular password won't work."
        case .yahoo:
            return "Yahoo requires an App Password — your regular password won't work."
        default:
            return nil
        }
    }

    private var appPasswordLink: String? {
        switch presetProvider {
        case .gmail:  return "https://support.google.com/accounts/answer/185833"
        case .yahoo:  return "https://help.yahoo.com/kb/generate-third-party-passwords-sln15241.html"
        default:      return nil
        }
    }

    private static func defaultServers(for provider: EmailProvider) -> (String, String, String, String) {
        switch provider {
        case .gmail:   return ("imap.gmail.com",          "993", "smtp.gmail.com",          "587")
        case .outlook: return ("outlook.office365.com",   "993", "smtp.office365.com",      "587")
        case .yahoo:   return ("imap.mail.yahoo.com",     "993", "smtp.mail.yahoo.com",     "465")
        default:       return ("",                         "993", "",                         "587")
        }
    }
}
