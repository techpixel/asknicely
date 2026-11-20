import Carbon.HIToolbox
import Foundation

enum SettingsKey {
    static let timeout = "timeoutSeconds"
    static let keyCode = "connectKeyCode"          // -1 = no shortcut
    static let modifiers = "connectKeyModifiers"   // Carbon modifier flags
    static let keyLabel = "connectKeyLabel"        // display character, e.g. "C"
}

struct Shortcut: Equatable {
    var code: UInt32
    var mods: UInt32
}

enum Settings {
    static let defaultTimeout = 8.0
    static let defaultKeyCode = Int(kVK_ANSI_C)
    static let defaultModifiers = Int(controlKey | optionKey)   // ⌃⌥C
    static let defaultKeyLabel = "C"

    static var timeout: Double {
        UserDefaults.standard.object(forKey: SettingsKey.timeout) as? Double ?? defaultTimeout
    }

    /// The Connect shortcut, or nil if the user cleared it.
    static var shortcut: Shortcut? {
        let d = UserDefaults.standard
        let code = d.object(forKey: SettingsKey.keyCode) as? Int ?? defaultKeyCode
        let mods = d.object(forKey: SettingsKey.modifiers) as? Int ?? defaultModifiers
        return code < 0 ? nil : Shortcut(code: UInt32(code), mods: UInt32(mods))
    }

    /// e.g. "⌃⌥C"
    static func display(label: String, modifiers: Int) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + label
    }
}
