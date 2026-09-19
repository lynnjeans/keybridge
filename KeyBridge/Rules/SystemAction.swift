import Carbon.HIToolbox
import Foundation

/// A macOS function that has a shortcut of its own in System Settings ›
/// Keyboard › Keyboard Shortcuts, which a rule can trigger by name (KB-051).
///
/// The rule stores the function, not keys: when it fires, KeyBridge posts
/// whatever shortcut the user has for it (`SymbolicHotKeys`), so a changed
/// shortcut keeps working. Raw values are saved in the configuration and
/// must never change.
enum SystemAction: String, Codable, CaseIterable, Sendable {
    case missionControl
    case applicationWindows
    case showDesktop
    /// Launchpad before macOS 26, Apps since.
    case apps
    case spaceLeft
    case spaceRight
    case spotlight

    /// The function's entry in `com.apple.symbolichotkeys`.
    var hotKeyID: Int {
        switch self {
        case .missionControl: 32
        case .applicationWindows: 33
        case .showDesktop: 36
        case .apps: 160
        case .spaceLeft: 79
        case .spaceRight: 81
        case .spotlight: 64
        }
    }

    /// The shortcut macOS ships with, which applies while the user's file has
    /// no entry for the function. Launchpad and Apps ship with none.
    var defaultShortcut: KeyCombo? {
        switch self {
        case .missionControl: KeyCombo([.control], .upArrow)
        case .applicationWindows: KeyCombo([.control], .downArrow)
        case .showDesktop: KeyCombo(.f11)
        case .apps: nil
        case .spaceLeft: KeyCombo([.control], .leftArrow)
        case .spaceRight: KeyCombo([.control], .rightArrow)
        case .spotlight: KeyCombo([.command], .space)
        }
    }

    /// An app in /System/Applications that does the same, opened when the
    /// function has no shortcut or it is switched off.
    var fallbackApplication: String? {
        switch self {
        case .missionControl: "com.apple.exposelauncher"
        case .apps:
            if #available(macOS 26, *) { "com.apple.apps.launcher" } else { "com.apple.launchpad.launcher" }
        default: nil
        }
    }
}

/// The system's own shortcuts, as the user has set them in System Settings ›
/// Keyboard › Keyboard Shortcuts.
struct SymbolicHotKeys {
    enum Shortcut: Equatable {
        case combo(KeyCombo)
        /// Switched off in System Settings.
        case off
        /// No shortcut at all: none assigned, and none shipped.
        case none
    }

    /// `AppleSymbolicHotKeys` from `com.apple.symbolichotkeys`: entries by ID,
    /// each `{enabled, value: {parameters: [character, key code, modifiers]}}`.
    /// Only functions whose shortcut differs from the shipped one have an entry.
    let entries: [String: Any]

    /// Read fresh from the preferences each time: the user may have changed a
    /// shortcut since the last use.
    static func current() -> SymbolicHotKeys {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain)
        return SymbolicHotKeys(entries: value as? [String: Any] ?? [:])
    }

    func shortcut(for action: SystemAction) -> Shortcut {
        guard let entry = entries[String(action.hotKeyID)] as? [String: Any] else {
            return action.defaultShortcut.map(Shortcut.combo) ?? .none
        }
        if let enabled = entry["enabled"] as? Bool, !enabled { return .off }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int], parameters.count == 3,
              parameters[1] != 0xFFFF,
              let keyCode = UInt16(exactly: parameters[1])
        else { return .none }
        let key = KeyCode(rawValue: keyCode)
        var modifiers = Self.modifiers(parameters[2])
        // Arrows and F-keys carry fn in the file however they are pressed.
        if key.carriesImplicitFunctionFlag { modifiers.remove(.function) }
        return .combo(KeyCombo(modifiers, key))
    }

    /// The file stores modifiers as event flags.
    private static func modifiers(_ flags: Int) -> Modifiers {
        var modifiers: Modifiers = []
        if flags & (1 << 17) != 0 { modifiers.insert(.shift) }
        if flags & (1 << 18) != 0 { modifiers.insert(.control) }
        if flags & (1 << 19) != 0 { modifiers.insert(.option) }
        if flags & (1 << 20) != 0 { modifiers.insert(.command) }
        if flags & (1 << 23) != 0 { modifiers.insert(.function) }
        return modifiers
    }
}
