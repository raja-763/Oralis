import SwiftUI

struct AccountSetupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var step: SetupStep = .choose
    @State private var provider: EmailProvider = .gmail
    @State private var displayName = ""
    @State private var emailAddress = ""
    @State private var password = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var smtpHost = ""
    @State private var smtpPort = "587"
    @State private var importedAccounts: [MacMailImporter.MailAccountConfig] = []

    enum SetupStep { case choose, oauth, manual, importing }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Add Email Account")
                .font(.title2.weight(.semibold))
                .padding()
                .accessibilityAddTraits(.isHeader)

            Divider()

            switch step {
            case .choose:  chooseView
            case .oauth:   oauthView
            case .manual:  manualView
            case .importing: importView
            }
        }
        .frame(width: 520)
        .onAppear { importedAccounts = MacMailImporter.importAccounts() }
    }

    // MARK: - Step: Choose provider

    @ViewBuilder private var chooseView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose your email provider:")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            // macOS Mail import (if accounts exist)
            if !importedAccounts.isEmpty {
                Button {
                    step = .importing
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("Import from macOS Mail")
                                .fontWeight(.semibold)
                            Text("\(importedAccounts.count) account(s) found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Import \(importedAccounts.count) account(s) from macOS Mail")
            }

            ForEach(EmailProvider.allCases) { p in
                Button {
                    provider = p
                    step = p.supportsOAuth ? .oauth : .manual
                } label: {
                    HStack {
                        Image(systemName: p.iconName)
                            .font(.title2)
                            .frame(width: 32)
                        Text(p.rawValue)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.rawValue). \(p.supportsOAuth ? "Sign in with your account." : "Enter IMAP and SMTP settings.")")
            }
        }
        .padding()

        Spacer()
        HStack {
            Button("Cancel") { dismiss() }
            Spacer()
        }
        .padding()
    }

    // MARK: - Step: OAuth

    @ViewBuilder private var oauthView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Sign in to \(provider.rawValue)")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                // Step 1: open browser
                VStack(alignment: .leading, spacing: 8) {
                    Text("Step 1 — Open sign-in page")
                        .font(.headline)
                    Text(provider.oauthInstructions)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open \(provider.rawValue) in Browser") {
                        if let url = provider.signInURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Open \(provider.rawValue) sign-in page in your default browser")
                }
                .padding()
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Step 2: enter details
                VStack(alignment: .leading, spacing: 12) {
                    Text("Step 2 — Enter your details")
                        .font(.headline)

                    TextField("Your name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Your name")

                    TextField("Email address (e.g. you@gmail.com)", text: $emailAddress)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Email address")

                    SecureField(provider.passwordLabel, text: $password)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(provider.passwordLabel)

                    Text(provider.passwordHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text("Your password is stored only in the macOS Keychain — never on any server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }

        HStack {
            Button("Back") { step = .choose }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Add Account") {
                let key = "oralis.token.\(UUID().uuidString)"
                KeychainService.shared.save(key: key, value: password)
                let acc = EmailAccount(
                    displayName: displayName.isEmpty ? emailAddress : displayName,
                    emailAddress: emailAddress,
                    provider: provider,
                    imapHost: provider.defaultIMAPHost,
                    imapPort: 993,
                    smtpHost: provider.defaultSMTPHost,
                    smtpPort: 587,
                    keychainToken: key
                )
                appState.addAccount(acc)
                appState.announce("\(emailAddress) added.")
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(emailAddress.isEmpty || password.isEmpty)
            .accessibilityLabel("Add \(provider.rawValue) account")
        }
        .padding()
    }

    // MARK: - Step: Manual IMAP

    @ViewBuilder private var manualView: some View {
        Form {
            Section("Account Info") {
                TextField("Your name", text: $displayName)
                    .accessibilityLabel("Display name")
                TextField("Email address", text: $emailAddress)
                    .accessibilityLabel("Email address")
                SecureField("Password", text: $password)
                    .accessibilityLabel("Password")
            }
            Section("Incoming (IMAP)") {
                TextField("imap.example.com", text: $imapHost)
                    .accessibilityLabel("IMAP host")
                TextField("993", text: $imapPort)
                    .accessibilityLabel("IMAP port")
            }
            Section("Outgoing (SMTP)") {
                TextField("smtp.example.com", text: $smtpHost)
                    .accessibilityLabel("SMTP host")
                TextField("587", text: $smtpPort)
                    .accessibilityLabel("SMTP port")
            }
        }
        .formStyle(.grouped)

        HStack {
            Button("Back") { step = .choose }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Add Account") {
                let key = "aria.imap.\(UUID().uuidString)"
                KeychainService.shared.save(key: key, value: password)
                let account = EmailAccount(
                    displayName: displayName.isEmpty ? emailAddress : displayName,
                    emailAddress: emailAddress,
                    provider: provider,
                    imapHost: imapHost,
                    imapPort: Int(imapPort) ?? 993,
                    smtpHost: smtpHost,
                    smtpPort: Int(smtpPort) ?? 587,
                    keychainToken: key
                )
                appState.addAccount(account)
                appState.announce("Account \(emailAddress) added.")
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(emailAddress.isEmpty || imapHost.isEmpty)
        }
        .padding()
    }

    // MARK: - Step: Import from macOS Mail

    @ViewBuilder private var importView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Found these accounts in macOS Mail:")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(importedAccounts, id: \.emailAddress) { config in
                Button {
                    let account = EmailAccount(
                        displayName: config.displayName,
                        emailAddress: config.emailAddress,
                        provider: config.provider,
                        imapHost: config.imapHost,
                        imapPort: config.imapPort,
                        smtpHost: config.smtpHost,
                        smtpPort: config.smtpPort,
                        importedFromMailApp: true
                    )
                    appState.addAccount(account)
                    appState.announce("\(config.emailAddress) imported.")
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: config.provider.iconName)
                        VStack(alignment: .leading) {
                            Text(config.displayName)
                                .fontWeight(.medium)
                            Text(config.emailAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Import")
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Import \(config.emailAddress) from macOS Mail")
            }
        }
        .padding()

        Spacer()
        HStack {
            Button("Back") { step = .choose }
            Spacer()
            Button("Cancel") { dismiss() }
        }
        .padding()
    }
}
