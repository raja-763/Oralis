import SwiftUI
import WebKit

struct EmailDetailView: View {
    let thread: EmailThread
    @EnvironmentObject var appState: AppState
    @State private var showReplySheet = false
    @State private var showLinkSheet  = false
    @State private var selectedLink: EmailLink?
    @State private var isReading     = false

    private var message: EmailMessage? { thread.latestMessage }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(thread.subject)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)

                    HStack {
                        Text("From: \(message?.from.display ?? "")")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let date = message?.date {
                            Text(date, style: .date)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal)

                Divider()

                // Body
                if let msg = message {
                    Text(msg.bodyPlain)
                        .padding(.horizontal)
                        .textSelection(.enabled)
                        .accessibilityLabel("Email body: \(msg.bodyPlain)")

                    // Links section
                    if !msg.links.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Links in this email")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.horizontal)

                            ForEach(msg.links) { link in
                                Button {
                                    selectedLink = link
                                    showLinkSheet = true
                                } label: {
                                    HStack {
                                        Image(systemName: "link")
                                        Text(link.title.isEmpty ? link.url.absoluteString : link.title)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Link: \(link.title.isEmpty ? link.url.absoluteString : link.title). Press to open by voice.")
                            }
                        }
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                    }

                    // Unsubscribe
                    if msg.hasUnsubscribeOption {
                        Button {
                            Task {
                                guard let acc = appState.selectedAccount else { return }
                                let service = EmailServiceFactory.service(for: acc)
                                do {
                                    try await service.unsubscribe(from: msg)
                                    appState.announce("Unsubscribed successfully.")
                                } catch {
                                    appState.announce("Unsubscribe failed: \(error.localizedDescription)")
                                }
                            }
                        } label: {
                            Label("Unsubscribe from this list", systemImage: "bell.slash.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .padding(.horizontal)
                        .accessibilityLabel("Unsubscribe from this mailing list by voice")
                    }

                    // Calendar invite
                    if let invite = msg.calendarInvite {
                        CalendarInviteCard(invite: invite)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .toolbar {
            ToolbarItemGroup {
                // Read aloud toggle
                Button {
                    if isReading {
                        appState.speech.stopSpeaking()
                        isReading = false
                    } else {
                        isReading = true
                        let body = message?.bodyPlain ?? ""
                        let subject = thread.subject
                        let from = message?.from.display ?? ""
                        appState.speech.speak("Email from \(from). Subject: \(subject). \(body)")
                    }
                } label: {
                    Label(isReading ? "Stop Reading" : "Read Aloud",
                          systemImage: isReading ? "stop.circle.fill" : "speaker.wave.2.fill")
                }
                .accessibilityLabel(isReading ? "Stop reading email aloud" : "Read this email aloud")
                .keyboardShortcut("R", modifiers: [.command, .option])

                // Reply
                Button { showReplySheet = true } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                }
                .accessibilityLabel("Reply to this email")
                .keyboardShortcut("R", modifiers: .command)

                // Delete
                Button(role: .destructive) {
                    appState.selectedThreadIDs = [thread.id]
                    Task { await appState.deleteSelected() }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityLabel("Delete this email")
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
        .sheet(isPresented: $showReplySheet) {
            if let msg = message {
                ComposeView(replyTo: msg)
            }
        }
        .sheet(item: $selectedLink) { link in
            LinkReaderView(url: link.url)
        }
        .navigationTitle(thread.subject)
    }
}

// MARK: - Calendar invite card

struct CalendarInviteCard: View {
    let invite: CalendarInvite
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Calendar Invite", systemImage: "calendar.badge.plus")
                .font(.headline)

            Text(invite.title)
                .fontWeight(.semibold)

            HStack {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(invite.startDate, style: .date) + Text(" at ") + Text(invite.startDate, style: .time)
            }
            .foregroundStyle(.secondary)

            if let url = invite.meetingURL {
                HStack {
                    Image(systemName: "video.fill").accessibilityHidden(true)
                    Text(url.host ?? "Virtual meeting")
                        .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 12) {
                Button("Accept") {
                    appState.announce("Calendar invite accepted for \(invite.title).")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityLabel("Accept this meeting invite")

                Button("Decline") {
                    appState.announce("Calendar invite declined for \(invite.title).")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel("Decline this meeting invite")

                Button("Join Meeting") {
                    if let url = invite.meetingURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(invite.meetingURL == nil)
                .accessibilityLabel(invite.meetingURL == nil ? "No meeting link available" : "Join the virtual meeting")
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(invite.accessibilityDescription)
    }
}
