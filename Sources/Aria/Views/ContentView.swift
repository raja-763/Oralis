import SwiftUI

/// Root container: three tabs — Talk, Browse, and Settings.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppTab = .talk

    enum AppTab { case talk, browse, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            TalkView()
                .tabItem {
                    Label("Talk", systemImage: "waveform.circle.fill")
                }
                .tag(AppTab.talk)

            BrowserView()
                .tabItem {
                    Label("Browse", systemImage: "globe")
                }
                .tag(AppTab.browse)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
        .frame(minWidth: 700, minHeight: 520)
        .sheet(isPresented: $appState.showAccountSetup) {
            AccountSetupView()
                .environmentObject(appState)
        }
    }
}
