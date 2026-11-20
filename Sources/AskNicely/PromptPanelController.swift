import AppKit
import SwiftUI

/// Borderless panel that is allowed to sit over the menu bar / notch area.
private final class FloatingPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosts the prompt in a non-activating floating panel pinned to the top-center of the screen.
@MainActor
final class PromptPanelController {
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
        panel.contentView = NSHostingView(rootView: AudioPromptView(model: model))
    }

    var isShowing: Bool { model.isVisible }

    func show(deviceName: String, onConnect: @escaping () -> Void) {
        hideWorkItem?.cancel()
        model.deviceName = deviceName
        model.isConnecting = false
        model.wasInteracted = false
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.onConnect = onConnect
        positionPanel()
        panel.orderFrontRegardless()
        // Flip on the next runloop tick so SwiftUI animates the slide-in.
        DispatchQueue.main.async {
            if self.model.reduceMotion {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.model.isVisible = true
                    self.model.isDetached = true
                }
                return
            }
            // Grow out of the notch while still attached to the top edge (Apple's snappy spring
            // with a touch of bounce, Dynamic Island-like)...
            withAnimation(.snappy(duration: 0.5, extraBounce: 0.1)) { self.model.isVisible = true }
            // ...then drop to the resting spot once it's wider than the notch.
            withAnimation(.snappy(duration: 0.45, extraBounce: 0.1).delay(0.12)) { self.model.isDetached = true }
        }
        // HIG: don't rely on motion alone to communicate. Announce the prompt to VoiceOver users.
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: "Audio detected, \(deviceName). Connect to this Mac?",
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    func hide() {
        guard model.isVisible else { return }
        if model.reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                model.isVisible = false
                model.isDetached = false
            }
        } else {
            // Rise and re-attach to the top edge first, then shrink back into the notch:
            // smooth, no bounce. Shrinking while still floating would leave a notch-shaped
            // blob hanging below the menu bar with a gap above it.
            withAnimation(.smooth(duration: 0.25)) { model.isDetached = false }
            withAnimation(.smooth(duration: 0.35).delay(0.1)) { model.isVisible = false }
        }
        let item = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: item)
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
