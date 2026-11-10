import SwiftUI

// MARK: - Settings category

enum SettingsCategory: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case voice    = "Voice"
    case updates  = "Updates"
    case about    = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .accounts: return "envelope.fill"
        case .voice:    return "speaker.wave.2.fill"
        case .updates:  return "arrow.triangle.2.circlepath"
        case .about:    return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .accounts: return .blue
        case .voice:    return .purple
        case .updates:  return .green
        case .about:    return .gray
        }
    }
}

// MARK: - Main settings view (System Settings style)

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var updater = UpdateChecker()
    @State private var selected: SettingsCategory? = .accounts
    @State private var showAddAccount = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // ── Sidebar ──────────────────────────────────────────────
            List(SettingsCategory.allCases, selection: $selected) { cat in
                Label {
                    Text(cat.rawValue)
                } icon: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(cat.iconColor)
                            .frame(width: 28, height: 28)
                        Image(systemName: cat.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
                }
                .tag(cat)
                .accessibilityLabel(cat.rawValue)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            // ── Detail pane ──────────────────────────────────────────
            Group {
                switch selected ?? .accounts {
                case .accounts: AccountsDetailView(showAdd: $showAddAccount)
                case .voice:    VoiceDetailView()
                case .updates:  UpdatesDetailView(updater: updater)
                case .about:    AboutDetailView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showAddAccount) {
            AccountSetupView().environmentObject(appState)
        }
        .task { await updater.checkForUpdates() }
    }
}

// MARK: - Accounts detail

struct AccountsDetailView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showAdd: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailHeader(
                    title: "Email Accounts",
                    subtitle: "Manage the accounts Oralis uses to fetch and send email."
                )

                if appState.accounts.isEmpty {
                    ContentUnavailableView(
                        "No accounts",
                        systemImage: "envelope.badge.slash",
                        description: Text("Add an account to start managing email with Oralis.")
                    )
                    .padding(.top, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.accounts.enumerated()), id: \.element.id) { idx, acc in
                            AccountDetailRow(account: acc) {
                                appState.removeAccount(acc)
                            }
                            if idx < appState.accounts.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showAdd = true
                } label: {
                    Label("Add Account", systemImage: "plus.circle.fill")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add a new email account")
            }
            .padding(24)
        }
    }
}

struct AccountDetailRow: View {
    let account: EmailAccount
    let onRemove: () -> Void
    @State private var showConfirm = false

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

            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .fontWeight(.medium)
                Text(account.emailAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(account.provider.rawValue)
                    if account.useOAuth {
                        Text("· SSO")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(role: .destructive) {
                showConfirm = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(account.displayName)")
            .confirmationDialog("Remove \(account.displayName)?", isPresented: $showConfirm, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { onRemove() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.displayName), \(account.emailAddress), \(account.provider.rawValue)\(account.useOAuth ? ", SSO" : "")")
    }
}

// MARK: - Voice detail

struct VoiceDetailView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice & Reading")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Customize how Oralis listens and reads your email aloud.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .padding(.bottom, 0)

            Divider()

            VoiceSettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Updates detail

struct UpdatesDetailView: View {
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailHeader(
                    title: "Updates",
                    subtitle: "Oralis checks GitHub automatically when you open Settings."
                )

                VStack(spacing: 0) {
                    // Current version row
                    SettingsRow(label: "Current Version", value: "v\(updater.currentVersion)")
                    Divider().padding(.leading, 16)

                    // Latest version row
                    HStack {
                        Text("Latest Version")
                            .foregroundStyle(.primary)
                        Spacer()
                        if updater.isChecking {
                            ProgressView().controlSize(.small)
                        } else if let v = updater.latestVersion {
                            Text("v\(v)")
                                .foregroundStyle(updater.updateAvailable ? .green : .secondary)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.06))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let err = updater.checkError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                if updater.updateAvailable {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Update Available")
                                    .fontWeight(.semibold)
                                Text("v\(updater.latestVersion ?? "") is ready to download.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            updater.openDownloadPage()
                        } label: {
                            Label("Download Update", systemImage: "arrow.down.circle.fill")
                                .font(.body.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .accessibilityLabel("Download Oralis version \(updater.latestVersion ?? "")")
                    }
                    .padding(16)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    Task { await updater.checkForUpdates() }
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(updater.isChecking)
                .accessibilityLabel("Check for updates now")

                Text("After downloading, open the DMG and drag Oralis to Applications, then run: xattr -cr /Applications/Oralis.app")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
        }
    }
}

// MARK: - About detail

struct AboutDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailHeader(
                    title: "About Oralis",
                    subtitle: "Voice-first, accessibility-first email for macOS."
                )

                VStack(spacing: 0) {
                    SettingsRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    Divider().padding(.leading, 16)
                    SettingsRow(label: "AI Model", value: "Claude Haiku (via proxy)")
                    Divider().padding(.leading, 16)
                    SettingsRow(label: "Inspired by", value: "Lumin for iOS")
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 10) {
                    LinkRow(label: "View Source on GitHub",   icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/raja-763/Oralis")
                    LinkRow(label: "Privacy & Security",     icon: "lock.shield.fill",                       url: "https://github.com/raja-763/Oralis#privacy--security")
                    LinkRow(label: "Report an Issue",        icon: "exclamationmark.bubble.fill",             url: "https://github.com/raja-763/Oralis/issues")
                }
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
    }
}

// MARK: - Shared sub-components

struct DetailHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct LinkRow: View {
    let label: String
    let icon: String
    let url: String
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(label)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }
}

// MARK: - Account row (kept for TalkView header use)

struct AccountRow: View {
    let account: EmailAccount

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.provider.iconName)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .fontWeight(.medium)
                Text(account.emailAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(account.provider.rawValue)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.displayName), \(account.emailAddress), \(account.provider.rawValue)")
    }
}
