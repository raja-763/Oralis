import SwiftUI

/// Root container: Talk and Settings tabs.
/// The browser runs in the background (driven by the AI); there is no Browse tab.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppTab = .talk

    enum AppTab { case talk, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            TalkView()
                .tabItem {
                    Label("Talk", systemImage: "waveform.circle.fill")
                }
                .tag(AppTab.talk)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
        .frame(minWidth: 480, minHeight: 520)
        .sheet(isPresented: $appState.showAccountSetup) {
            AccountSetupView()
                .environmentObject(appState)
        }
        // Call overlay — shown for sighted users only.
        // VoiceOver users stay in the main window; audio feedback comes via VO announcements.
        .sheet(isPresented: .init(
            get: { appState.isConversationMode && !SpeechService.isVoiceOverActive },
            set: { if !$0 { appState.stopConversationMode() } }
        )) {
            CallView()
                .environmentObject(appState)
                .frame(minWidth: 480, minHeight: 540)
        }
        // Switch to Settings tab when triggered from menu bar or app menu
        .onReceive(NotificationCenter.default.publisher(for: .oralisOpenSettings)) { _ in
            selectedTab = .settings
        }
    }
}
