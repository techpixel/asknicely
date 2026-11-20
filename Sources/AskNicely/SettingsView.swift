import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.timeout) private var timeout = Settings.defaultTimeout
    @AppStorage(SettingsKey.keyCode) private var keyCode = Settings.defaultKeyCode
    @AppStorage(SettingsKey.modifiers) private var modifiers = Settings.defaultModifiers
    @AppStorage(SettingsKey.keyLabel) private var keyLabel = Settings.defaultKeyLabel

    var body: some View {
        Form {
            Section {
                LabeledContent("Dismiss after") {
                    HStack {
                        Slider(value: $timeout, in: 2...30, step: 1)
                            .frame(width: 180)
                        Text("\(Int(timeout)) s")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Hovering over the prompt pauses the timer. Clicking it keeps it open.")
            }

            Section {
                LabeledContent("Connect shortcut") {
                    ShortcutRecorder(keyCode: $keyCode, modifiers: $modifiers, keyLabel: $keyLabel)
                }
            } footer: {
                Text("Presses Connect while the prompt is showing. Click the field, then press a shortcut with at least one of ⌃ ⌥ ⌘.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Click to record; press a combo to set it; Esc cancels.
private struct ShortcutRecorder: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var keyLabel: String

    @State private var recording = false
    @State private var monitor: Any?

    private var isSet: Bool { keyCode >= 0 }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { recording ? stop() : start() }) {
                Text(recording ? "Press shortcut…"
                     : isSet ? Settings.display(label: keyLabel, modifiers: modifiers) : "Not set")
                    .frame(minWidth: 110)
            }
            .controlSize(.regular)

            if isSet && !recording {
                Button {
                    keyCode = -1
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var carbon = 0
            if flags.contains(.control) { carbon |= controlKey }
            if flags.contains(.option) { carbon |= optionKey }
            if flags.contains(.shift) { carbon |= shiftKey }
            if flags.contains(.command) { carbon |= cmdKey }
            // Require ⌃, ⌥ or ⌘ so a bare letter can't be grabbed globally.
            guard carbon & (controlKey | optionKey | cmdKey) != 0 else { NSSound.beep(); return nil }
            keyCode = Int(event.keyCode)
            modifiers = carbon
            keyLabel = (event.charactersIgnoringModifiers ?? "?").uppercased()
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
