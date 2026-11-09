import SwiftUI

struct EmailListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""

    var filtered: [EmailThread] {
        guard !searchText.isEmpty else { return appState.threads }
        return appState.threads.filter {
            $0.subject.localizedCaseInsensitiveContains(searchText) ||
            $0.participants.contains { $0.display.localizedCaseInsensitiveContains(searchText) } ||
            $0.snippet.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedThread?.id },
            set: { id in appState.selectedThread = appState.threads.first { $0.id == id } }
        )) {
            ForEach(filtered) { thread in
                EmailThreadRow(thread: thread,
                               isSelected: appState.selectedThreadIDs.contains(thread.id))
                    .tag(thread.id)
                    .accessibilityLabel(thread.accessibilityLabel)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            appState.selectedThreadIDs = [thread.id]
                            Task { await appState.deleteSelected() }
                        } label: { Label("Delete", systemImage: "trash") }

                        Button {
                            appState.selectedThreadIDs = [thread.id]
                            Task { await appState.archiveSelected() }
                        } label: { Label("Archive", systemImage: "archivebox") }
                            .tint(.blue)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            appState.selectedThreadIDs.insert(thread.id)
                        } label: { Label("Select", systemImage: "checkmark.circle") }
                            .tint(.green)
                    }
            }
        }
        .searchable(text: $searchText, prompt: "Search emails")
        .navigationTitle(appState.selectedAccount?.displayName ?? "Inbox")
        .toolbar {
            ToolbarItem {
                Button {
                    if let acc = appState.selectedAccount {
                        Task { await appState.refreshInbox(for: acc) }
                    }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .accessibilityLabel("Refresh inbox")
            }
        }
        .onChange(of: searchText) { _, query in
            guard !query.isEmpty else { return }
            Task {
                guard let acc = appState.selectedAccount else { return }
                let service = EmailServiceFactory.service(for: acc)
                if let results = try? await service.searchThreads(query: query) {
                    await MainActor.run { appState.threads = results }
                }
            }
        }
        .overlay {
            if appState.threads.isEmpty {
                ContentUnavailableView("No emails", systemImage: "envelope",
                    description: Text("Your inbox is empty or still loading."))
            }
        }
    }
}

struct EmailThreadRow: View {
    let thread: EmailThread
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(thread.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(thread.participants.first?.display ?? "Unknown")
                        .fontWeight(thread.isRead ? .regular : .semibold)
                        .lineLimit(1)
                    Spacer()
                    Text(thread.latestDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(thread.subject)
                    .lineLimit(1)
                    .foregroundStyle(thread.isRead ? .secondary : .primary)
                Text(thread.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }
}
