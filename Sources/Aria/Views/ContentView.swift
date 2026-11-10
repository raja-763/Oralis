import SwiftUI

/// Root container: two tabs — Talk and Settings.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppTab = .talk

    enum AppTab { case talk, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            TalkView()
                .tabItem {
                    Label("Talk to Oralis", systemImage: "waveform.circle.fill")
                }
                .tag(AppTab.talk)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
        .frame(minWidth: 600, minHeight: 500)
        .sheet(isPresented: $appState.showAccountSetup) {
            AccountSetupView()
                .environmentObject(appState)
        }
    }
}
