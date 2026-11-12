import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Owns the menu bar status item and the floating panel.
@MainActor
final class MenuBarController: NSObject, ObservableObject {

    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private var eventMonitor: Any?

    // Current hotkey (default ⌥Space)
    @Published var shortcutKeyCode: UInt32   = UInt32(kVK_Space)
    @Published var shortcutModifiers: UInt32 = UInt32(optionKey)

    private weak var appState: AppState?
    private var panelSetUp = false

    // Called from AriaApp.onChange when appState changes
    func refreshPanel(appState: AppState) {
        guard !panelSetUp else { return }
        self.appState = appState
        panelSetUp = true
        buildStatusItem()
        buildPanel(appState: appState)
        loadSavedShortcut()
        installEventMonitor()
    }

    // MARK: - Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "waveform.circle.fill",
                               accessibilityDescription: "Oralis")
        button.image?.isTemplate = true
        button.toolTip = "Oralis — click to open, Option+Space from anywhere"
        button.setAccessibilityLabel("Oralis voice assistant")

        // Attach the dropdown menu so a click shows it
        statusItem?.menu = buildStatusMenu()

        // Listen for the keyboard shortcut notification from app menus
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePanel),
            name: .oralisTogglePanel,
            object: nil
        )
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        // ── Conversation ───────────────────────────────────────────────
        let startItem = NSMenuItem(title: "Start Conversation",
                                   action: #selector(menuStartConversation),
                                   keyEquivalent: "")
        startItem.target = self
        startItem.image  = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        menu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop Conversation",
                                  action: #selector(menuStopConversation),
                                  keyEquivalent: "")
        stopItem.target = self
        stopItem.image  = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: nil)
        menu.addItem(stopItem)

        menu.addItem(.separator())

        // ── Window ─────────────────────────────────────────────────────
        let panelItem = NSMenuItem(title: "Show Panel",
                                   action: #selector(togglePanel),
                                   keyEquivalent: " ")
        panelItem.keyEquivalentModifierMask = [.option]
        panelItem.target = self
        panelItem.image  = NSImage(systemSymbolName: "rectangle.inset.filled", accessibilityDescription: nil)
        menu.addItem(panelItem)

        let windowItem = NSMenuItem(title: "Open Oralis Window",
                                    action: #selector(openMainWindow),
                                    keyEquivalent: "")
        windowItem.target = self
        windowItem.image  = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(windowItem)

        menu.addItem(.separator())

        // ── Inbox quick actions ────────────────────────────────────────
        let checkItem = NSMenuItem(title: "Check Inbox",
                                   action: #selector(menuCheckInbox),
                                   keyEquivalent: "")
        checkItem.target = self
        checkItem.image  = NSImage(systemSymbolName: "tray.fill", accessibilityDescription: nil)
        menu.addItem(checkItem)

        let calItem = NSMenuItem(title: "Today's Calendar",
                                 action: #selector(menuCheckCalendar),
                                 keyEquivalent: "")
        calItem.target = self
        calItem.image  = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
        menu.addItem(calItem)

        menu.addItem(.separator())

        // ── Settings & Quit ────────────────────────────────────────────
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        settingsItem.image  = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Oralis",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu actions

    @objc private func menuStartConversation() {
        NSApp.activate(ignoringOtherApps: true)
        appState?.startConversationMode()
    }

    @objc private func menuStopConversation() {
        appState?.stopConversationMode()
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where !(w is FloatingPanel) {
            w.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func menuCheckInbox() {
        NSApp.activate(ignoringOtherApps: true)
        appState?.sendAgentMessage("Read my latest emails and give me a summary.")
    }

    @objc private func menuCheckCalendar() {
        NSApp.activate(ignoringOtherApps: true)
        appState?.sendAgentMessage("What's on my calendar today?")
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openMainWindow()
        // Post notification that ContentView listens to for showing settings
        NotificationCenter.default.post(name: .oralisOpenSettings, object: nil)
    }

    // MARK: - Floating panel

    private func buildPanel(appState: AppState) {
        let p = FloatingPanel()
        let host = NSHostingView(rootView:
            FloatingPanelView()
                .environmentObject(appState)
        )
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 580)
        p.contentView = host
        p.delegate = self
        self.panel = p
    }

    @objc func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            positionNearStatusItem()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func positionNearStatusItem() {
        guard let panel,
              let button = statusItem?.button,
              let buttonWindow = button.window
        else { return }
        let btnFrame   = buttonWindow.convertToScreen(button.frame)
        let panelSize  = panel.frame.size
        let screen     = buttonWindow.screen?.visibleFrame ?? .zero
        var origin = CGPoint(
            x: btnFrame.midX  - panelSize.width  / 2,
            y: btnFrame.minY  - panelSize.height - 8
        )
        origin.x = max(screen.minX + 8, min(origin.x, screen.maxX - panelSize.width  - 8))
        origin.y = max(screen.minY + 8, origin.y)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Global keyboard shortcut

    func installEventMonitor() {
        if let old = eventMonitor { NSEvent.removeMonitor(old) }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleGlobalKey(event) }
        }
    }

    private func handleGlobalKey(_ event: NSEvent) {
        let flags = event.modifierFlags.carbonFlags
        guard flags == shortcutModifiers,
              UInt32(event.keyCode) == shortcutKeyCode
        else { return }
        togglePanel()
    }

    func updateShortcut(keyCode: UInt32, modifiers: UInt32) {
        shortcutKeyCode   = keyCode
        shortcutModifiers = modifiers
        UserDefaults.standard.set(keyCode,   forKey: "oralis.hotkey.keyCode")
        UserDefaults.standard.set(modifiers, forKey: "oralis.hotkey.modifiers")
        installEventMonitor()
    }

    func loadSavedShortcut() {
        let kc = UserDefaults.standard.object(forKey: "oralis.hotkey.keyCode")   as? UInt32
        let m  = UserDefaults.standard.object(forKey: "oralis.hotkey.modifiers") as? UInt32
        if let kc, let m {
            shortcutKeyCode   = kc
            shortcutModifiers = m
        }
    }
}

// MARK: - NSWindowDelegate

extension MenuBarController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        panel?.orderOut(nil)
    }
}

// MARK: - Floating panel window

final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
            styleMask:   [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing:     .buffered,
            defer:       false
        )
        isMovableByWindowBackground  = true
        isFloatingPanel              = true
        level                        = .floating
        titlebarAppearsTransparent   = true
        titleVisibility              = .hidden
        backgroundColor              = .clear
        hasShadow                    = true
        isReleasedWhenClosed         = false
        collectionBehavior           = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { true }
}

// MARK: - NSEvent.ModifierFlags → Carbon modifier mask

private extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var c: UInt32 = 0
        if contains(.command) { c |= UInt32(cmdKey) }
        if contains(.option)  { c |= UInt32(optionKey) }
        if contains(.shift)   { c |= UInt32(shiftKey) }
        if contains(.control) { c |= UInt32(controlKey) }
        return c
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let oralisOpenSettings = Notification.Name("oralis.openSettings")
    static let oralisTogglePanel  = Notification.Name("oralis.togglePanel")
}
