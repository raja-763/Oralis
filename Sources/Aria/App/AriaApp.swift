import SwiftUI

@main
struct AriaApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.showOnboarding {
                OnboardingView()
                    .environmentObject(appState)
                    .frame(minWidth: 680, minHeight: 540)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            AriaCommands(appState: appState)
        }
    }
}
