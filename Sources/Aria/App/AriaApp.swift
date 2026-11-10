import SwiftUI
import AppKit

@main
struct OralisApp: App {
    @NSApplicationDelegateAdaptor(OralisAppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.showOnboarding {
                OnboardingView()
                    .environmentObject(appState)
                    .frame(minWidth: 540, minHeight: 480)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Toggle Oralis Panel") {
                    appDelegate.menuBar.togglePanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
            }
        }
        // Pass appState to the delegate once it's available
        .onChange(of: appState.accounts.count) { _, _ in
            appDelegate.menuBar.refreshPanel(appState: appState)
        }
    }

}

// MARK: - App Delegate

@MainActor
final class OralisAppDelegate: NSObject, NSApplicationDelegate {
    let menuBar = MenuBarController()
    private var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // appState is wired via refreshPanel from the Scene
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first(where: { !($0 is FloatingPanel) })?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
