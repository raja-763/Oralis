import SwiftUI

/// Appears in the toolbar when one or more threads are selected.
/// Gives quick access to bulk delete, archive, mark-read, and move-to-spam.
struct BatchActionBar: View {
    @EnvironmentObject var appState: AppState

    var count: Int { appState.selectedThreadIDs.count }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count) selected")
                .font(.callout.weight(.semibold))
                .accessibilityLabel("\(count) emails selected")

            Button {
                Task { await appState.deleteSelected() }
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityLabel("Delete \(count) emails")

            Button {
                Task { await appState.archiveSelected() }
            } label: {
                Label("Archive", systemImage: "archivebox.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Archive \(count) emails")

            Button {
                guard let acc = appState.selectedAccount else { return }
                let service = EmailServiceFactory.service(for: acc)
                let ids = Array(appState.selectedThreadIDs)
                Task {
                    try? await service.markRead(ids: ids, read: true)
                    appState.selectedThreadIDs.removeAll()
                    appState.announce("Marked \(ids.count) emails as read.")
                }
            } label: {
                Label("Mark Read", systemImage: "envelope.open.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Mark \(count) emails as read")

            Button {
                guard let acc = appState.selectedAccount else { return }
                let service = EmailServiceFactory.service(for: acc)
                let ids = Array(appState.selectedThreadIDs)
                Task {
                    try? await service.moveToSpam(ids: ids)
                    appState.threads.removeAll { appState.selectedThreadIDs.contains($0.id) }
                    appState.selectedThreadIDs.removeAll()
                    appState.announce("Moved \(ids.count) emails to spam.")
                }
            } label: {
                Label("Spam", systemImage: "xmark.bin.fill")
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .accessibilityLabel("Move \(count) emails to spam")

            Button {
                appState.selectedThreadIDs.removeAll()
                appState.announce("Selection cleared.")
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear selection")
        }
    }
}
