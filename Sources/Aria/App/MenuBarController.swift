import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Owns the menu bar status item and the floating panel.
@MainActor
final class MenuBarController: NSObject, ObservableObject {

    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private var eventMonitor: Any?

    // Current shortcut (default ⌘⌥Space)
    @Published var shortcutKeyCode: UInt32   = UInt32(kVK_Space)
    @Published var shortcutModifiers: UInt32 = UInt32(cmdKey | optionKey)

    private var appState: AppState?
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
        button.action = #selector(togglePanel)
        button.target = self
        button.toolTip = "Oralis — click or press ⌘⌥Space"
        button.setAccessibilityLabel("Oralis menu bar button — toggle voice panel")
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

    // MARK: - Global keyboard shortcut (NSEvent monitor)

    func installEventMonitor() {
        if let old = eventMonitor { NSEvent.removeMonitor(old) }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalKey(event)
            }
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

// MARK: - NSWindowDelegate (dismiss on click-away)

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
        isMovableByWindowBackground = true
        isFloatingPanel  = true
        level            = .floating
        titlebarAppearsTransparent = true
        titleVisibility  = .hidden
        backgroundColor  = .clear
        hasShadow        = true
        isReleasedWhenClosed = false
        collectionBehavior   = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
