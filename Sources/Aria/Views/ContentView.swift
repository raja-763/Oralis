import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } content: {
            EmailListView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            if let thread = appState.selectedThread {
                EmailDetailView(thread: thread)
            } else {
                Text("Select an email to read it")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No email selected. Use the email list to pick one.")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if appState.showAgentPanel {
                AgentPanelView()
                    .frame(width: 380, height: 520)
                    .padding(16)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.showAgentPanel.toggle()
                } label: {
                    Label("AI Assistant", systemImage: "waveform.circle.fill")
                }
                .accessibilityLabel(appState.showAgentPanel ? "Close AI Assistant" : "Open AI Assistant")
                .keyboardShortcut("A", modifiers: [.command, .option])
            }

            if !appState.selectedThreadIDs.isEmpty {
                ToolbarItem {
                    BatchActionBar()
                }
            }
        }
        .sheet(isPresented: $appState.showAccountSetup) {
            AccountSetupView()
        }
        .animation(.easeInOut(duration: 0.2), value: appState.showAgentPanel)
    }
}
