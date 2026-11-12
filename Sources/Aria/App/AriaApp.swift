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
                    .sheet(isPresented: Binding(
                        get: { appState.accounts.isEmpty && appState.showAccountSetup },
                        set: { appState.showAccountSetup = $0 }
                    )) {
                        AccountSetupView().environmentObject(appState)
                    }
                    .onAppear {
                        if appState.accounts.isEmpty {
                            appState.showAccountSetup = true
                        }
                        // Boot menu bar on first appearance
                        appDelegate.menuBar.refreshPanel(appState: appState)
                    }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands {
            OralisCommands(appState: appState)
        }
        // Keep menu bar booted after account changes
        .onChange(of: appState.accounts.count) { _, _ in
            appDelegate.menuBar.refreshPanel(appState: appState)
        }
    }
}

// MARK: - App Delegate

@MainActor
final class OralisAppDelegate: NSObject, NSApplicationDelegate {
    let menuBar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Customize the app-level About panel title
        NSApplication.shared.applicationIconImage = NSImage(systemSymbolName: "waveform.circle.fill",
                                                             accessibilityDescription: "Oralis")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first(where: { !($0 is FloatingPanel) })?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // Keep the app running even with no windows (menu bar app pattern)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
