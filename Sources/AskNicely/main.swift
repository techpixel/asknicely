import AppKit
import SwiftUI
@preconcurrency import IOBluetooth

/// Polls audio + AirPods state and shows/hides the prompt.
///
/// Show when:  Mac output audio has been playing for a moment
///             AND a paired AirPods is nearby but not connected to this Mac
///             AND the user hasn't dismissed the prompt for this playback session.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panel = PromptPanelController()
    private let airPods = AirPodsMonitor()
    private let hotKey = HotKey()
    private var registeredShortcut: Shortcut?
    private var timer: Timer?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    private let demo = CommandLine.arguments.contains("--demo")
    private let audioDebounce = 2   // seconds of continuous audio before showing
    private var audioSeconds = 0
    private var dismissedThisSession = false
    private var shownSeconds = 0
    private var demoIdleSeconds = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        hotKey.onPress = { [weak self] in self?.connectViaShortcut() }
        airPods.start()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
        showSettings()   // opening the app shows its settings
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Settings window + menu bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "airpodspro", accessibilityDescription: "AskNicely")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AskNicely", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "AskNicely Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Prompt logic

    private func tick() {
        let playing = demo ? true : AudioMonitor.isOutputRunning()
        audioSeconds = playing ? audioSeconds + 1 : 0
        if !playing { dismissedThisSession = false }
        // Demo mode: audio never "stops", so re-arm a few seconds after each dismissal.
        if demo, dismissedThisSession, !panel.isShowing {
            demoIdleSeconds += 1
            if demoIdleSeconds >= 3 { dismissedThisSession = false; audioSeconds = 0; demoIdleSeconds = 0 }
        }

        let candidate = demo ? nil : airPods.nearbyCandidate()
        let hasTarget = demo || candidate != nil
        if panel.isShowing, !panel.model.isConnecting, !panel.model.wasInteracted {
            if !panel.isMouseOverPill {   // hovering pauses the countdown; it resumes after the mouse leaves
                shownSeconds += 1
                if Double(shownSeconds) >= Settings.timeout { dismissedThisSession = true }
            }
        }
        let shouldShow = audioSeconds >= audioDebounce && hasTarget && !dismissedThisSession

        if shouldShow, !panel.isShowing {
            shownSeconds = 0
            // Real paired-device name (e.g. "<Name>’s AirPods Pro"); generic fallback for demo mode.
            panel.show(deviceName: candidate?.name ?? "AirPods") { [weak self] in self?.connect(candidate) }
        } else if !shouldShow, panel.isShowing {
            panel.hide()
        }
        updateHotKey()
    }

    /// The Connect shortcut is only registered while the prompt is on screen.
    private func updateHotKey() {
        guard panel.isShowing, let shortcut = Settings.shortcut else {
            hotKey.unregister()
            registeredShortcut = nil
            return
        }
        if registeredShortcut != shortcut {
            hotKey.register(shortcut)
            registeredShortcut = shortcut
        }
    }

    private func connectViaShortcut() {
        guard panel.isShowing, !panel.model.isConnecting else { return }
        panel.model.onConnect()
    }

    private func connect(_ target: KnownAirPods?) {
        panel.model.isConnecting = true
        guard let target else { // demo mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                dismissedThisSession = true
                panel.hide()
            }
            return
        }
        let device = target.device
        DispatchQueue.global().async {
            _ = device.openConnection()
            DispatchQueue.main.async { [self] in
                dismissedThisSession = true
                panel.hide()
            }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
