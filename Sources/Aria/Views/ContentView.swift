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
    }
}
