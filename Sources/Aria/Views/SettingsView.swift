import SwiftUI

/// Settings screen — accounts and voice preferences.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var updater = UpdateChecker()
    @State private var showAddAccount = false
    @State private var showVoiceSettings = false

    var body: some View {
        NavigationStack {
            List {
                // ── Accounts ─────────────────────────────────────────
                Section {
                    if appState.accounts.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text("No accounts connected.")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("No email accounts connected")
                    } else {
                        ForEach(appState.accounts) { acc in
                            AccountRow(account: acc)
                        }
                        .onDelete { indices in
                            indices.forEach { appState.removeAccount(appState.accounts[$0]) }
                        }
                    }

                    Button {
                        showAddAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add a new email account")
                } header: {
                    Text("Email Accounts")
                        .accessibilityAddTraits(.isHeader)
                }

                // ── Voice ────────────────────────────────────────────
                Section {
                    NavigationLink {
                        VoiceSettingsView()
                            .environmentObject(appState)
                    } label: {
                        Label("Voice & Reading", systemImage: "speaker.wave.2.fill")
                    }
                    .accessibilityLabel("Open voice and reading settings")
                } header: {
                    Text("Voice")
                        .accessibilityAddTraits(.isHeader)
                }

                // ── Updates ──────────────────────────────────────────
                Section {
                    if updater.updateAvailable, let latest = updater.latestVersion {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Update Available: v\(latest)")
                                    .fontWeight(.medium)
                                Text("Current: v\(updater.currentVersion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Download") {
                                updater.openDownloadPage()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Update available: version \(latest). Press Download to get it.")
                    } else if updater.isChecking {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityHidden(true)
                            Text("Checking for updates…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let err = updater.checkError {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else if let latest = updater.latestVersion {
                        LabeledContent("Version", value: "v\(updater.currentVersion) (up to date)")
                            .accessibilityLabel("Version \(updater.currentVersion), up to date")
                            .foregroundStyle(.secondary)
                        let _ = latest // silence unused warning
                    } else {
                        LabeledContent("Version", value: "v\(updater.currentVersion)")
                    }

                    Button {
                        Task { await updater.checkForUpdates() }
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                    }
                    .disabled(updater.isChecking)
                    .accessibilityLabel("Check for updates now")
                } header: {
                    Text("Updates")
                        .accessibilityAddTraits(.isHeader)
                }

                // ── About ────────────────────────────────────────────
                Section {
                    LabeledContent("AI Model", value: "Claude Haiku (via proxy)")
                    Link(destination: URL(string: "https://github.com/raja-763/Oralis")!) {
                        Label("View Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .accessibilityLabel("View Oralis source code on GitHub")
                    Link(destination: URL(string: "https://github.com/raja-763/Oralis#privacy--security")!) {
                        Label("Privacy & Security", systemImage: "lock.shield.fill")
                    }
                    .accessibilityLabel("Read the privacy and security policy")
                } header: {
                    Text("About")
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .navigationTitle("Settings")
            .task { await updater.checkForUpdates() }
        }
        .sheet(isPresented: $showAddAccount) {
            AccountSetupView()
                .environmentObject(appState)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Account row

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
