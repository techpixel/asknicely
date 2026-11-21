import AppKit
import SwiftUI

/// Borderless panel that is allowed to sit over the menu bar / notch area.
private final class FloatingPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    // MARK: Active-appearance glass (PRIVATE API)
    //
    // macOS draws Liquid Glass flat/opaque in windows without active appearance, and this panel is
    // never key (by design, so it never steals keyboard focus). There is no public way to force the
    // active look, so these override NSWindow's private appearance queries to report "active"
    // without actually becoming key. Undocumented: may stop working or change on any macOS update;
    // if these selectors disappear the overrides are simply never called (glass falls back to flat).
    // Pass `--no-active-glass` to disable for comparison.
    static let forceActiveGlass = !CommandLine.arguments.contains("--no-active-glass")

    @objc func _hasActiveAppearance() -> Bool { Self.forceActiveGlass || isKeyWindow }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { Self.forceActiveGlass || isKeyWindow }
    @objc func _hasKeyAppearance() -> Bool { Self.forceActiveGlass || isKeyWindow }
    @objc func hasKeyAppearance() -> Bool { Self.forceActiveGlass || isKeyWindow }

    /// Whether AppKit still implements the private queries overridden above. If Apple removes or
    /// renames them, our overrides are never consulted and the glass would render flat, so the
    /// prompt stays notch-black instead. (Can't detect Apple keeping them but no longer using
    /// them for glass.)
    static let canForceActiveGlass: Bool = {
        guard #available(macOS 26.0, *), forceActiveGlass else { return false }
        return ["_hasActiveAppearance", "_hasActiveAppearanceIgnoringKeyFocus",
                "_hasKeyAppearance", "hasKeyAppearance"]
            .allSatisfy { class_getInstanceMethod(NSWindow.self, NSSelectorFromString($0)) != nil }
    }()
}

/// Hosts the prompt in a non-activating floating panel pinned to the top-center of the screen.
@MainActor
final class PromptPanelController {
    /// Show and hide share one timeline, so each takes the same time. It is driven linearly; the
    /// pacing (quick lead-in, slower drip, settle) lives in `LiquidDropMorphView.pace(_:)`, which is
    /// symmetric, so the exit is the entrance played backwards.
    private static var morphDuration: Double { Double(MorphTuning.shared.duration) }
    private static var morphAnimation: Animation { .linear(duration: morphDuration) }

    let model = PromptModel()
    private let panel: FloatingPanel
    private var hideWorkItem: DispatchWorkItem?

    init() {
        panel = FloatingPanel(contentRect: .zero,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu + 3   // above the menu bar / notch area
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        model.glassAvailable = FloatingPanel.canForceActiveGlass
        let host = NSHostingView(rootView: AudioPromptView(model: model))
        // Don't let SwiftUI resize the panel to the pill's animating size: AppKit resizes from
        // the left edge, which makes the centered pill jerk sideways while it morphs.
        host.sizingOptions = []
        panel.contentView = host
    }

    var isShowing: Bool { model.isVisible }

    func show(deviceName: String, onConnect: @escaping () -> Void) {
        hideWorkItem?.cancel()
        model.deviceName = deviceName
        model.isConnecting = false
        model.isConnected = false
        model.batteryPercent = nil
        model.wasInteracted = false
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.onConnect = onConnect
        model.isVisible = false
        model.progress = 0.0
        model.wobblePhase = 0
        positionPanel()
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        CATransaction.flush()
        // Flip on the next runloop tick so SwiftUI animates the water-droplet morph from the
        // committed initial layout in one continuous liquid motion.
        DispatchQueue.main.async {
            let anim: Animation = self.model.reduceMotion
                ? .easeInOut(duration: 0.25)
                : Self.morphAnimation
            withAnimation(anim) {
                self.model.isVisible = true
                self.model.progress = 1.0
            }
            // Land with a liquid jiggle: the wobble runs on its own clock, starting as the morph settles.
            if !self.model.reduceMotion {
                let t = MorphTuning.shared
                withAnimation(.linear(duration: Double(MorphTuning.wobbleLength))
                    .delay(Self.morphDuration * Double(t.wobbleStart))) {
                    self.model.wobblePhase = 1
                }
            }
        }
        // HIG: don't rely on motion alone to communicate. Announce the prompt to VoiceOver users.
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: "Audio detected, \(deviceName). Connect to this Mac?",
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    /// Swap to the "Connected" state (battery ring) in place; the caller hides it afterwards.
    func showConnected(batteryPercent: Int?) {
        model.batteryPercent = batteryPercent
        withAnimation(model.reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3)) {
            model.isConnecting = false
            model.isConnected = true
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: "Connected" + (batteryPercent.map { ", battery \($0) percent" } ?? ""),
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    func hide() {
        guard model.isVisible else { return }
        // No wobble on the way out (its value at the end of the clock is ~0, so this doesn't jump).
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { model.wobblePhase = 0 }
        let anim: Animation = model.reduceMotion
            ? .easeInOut(duration: 0.25)
            : Self.morphAnimation
        withAnimation(anim) {
            model.isVisible = false
            model.progress = 0.0
        }
        let item = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.morphDuration + 0.1, execute: item)
    }

    /// Whether the mouse is currently over the pill (screen coordinates, so it works while the
    /// panel is never key/active).
    var isMouseOverPill: Bool {
        guard model.isVisible else { return false }
        let content = AudioPromptView.contentSize
        let top = panel.frame.maxY - model.topInset - AudioPromptView.topGap
        let rect = NSRect(x: panel.frame.midX - content.width / 2, y: top - content.height,
                          width: content.width, height: content.height)
        return rect.contains(NSEvent.mouseLocation)
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // Notch size: height from the top safe-area inset, width from the gap between the
        // left/right menu-bar areas.
        var notch = CGSize.zero
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = CGSize(width: screen.frame.width - left.width - right.width,
                           height: screen.safeAreaInsets.top)
        }
        model.notchSize = notch
        // Menu bar height (== notch height on notch Macs); the pill rests just below it.
        let inset = max(screen.frame.maxY - screen.visibleFrame.maxY, notch.height)
        model.topInset = inset

        let margin = AudioPromptView.shadowMargin
        let content = AudioPromptView.contentSize
        let width = content.width + margin * 2
        let height = inset + AudioPromptView.topGap + content.height + margin

        let x = screen.frame.midX - width / 2
        panel.setFrame(NSRect(x: x, y: screen.frame.maxY - height, width: width, height: height), display: true)
    }
}
