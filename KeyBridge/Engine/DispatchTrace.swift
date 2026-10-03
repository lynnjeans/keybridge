import Carbon.HIToolbox
import Foundation

/// One press as the dispatcher saw it, for a diagnostic recording (KB-247):
/// what came in, which keyboard it was taken for, the app in front, and the
/// rule it matched, if any.
struct DispatchTrace: Sendable {
    var trigger: Trigger
    var keyboard: KeyboardAttribution
    var frontmostBundleID: String?
    /// The rule that matched; nil when the press went on unchanged.
    var rule: Rule?

    /// Which keyboard a press was taken for. Settings kept per keyboard
    /// apply only when it is known.
    enum KeyboardAttribution: Sendable, Equatable {
        case keyboard(Keyboard)
        /// A sender that no registry lookup turned into a keyboard: the
        /// press got the general settings.
        case unknown(sender: UInt64)
        /// Posted by software, which names no sender.
        case software
        /// Clicks and modifier taps follow the keyboard the last modifier
        /// came from; nil when that was not told.
        case lastModifier(Keyboard?)
    }

    /// Whether the press belongs in a recording. Plain typing never does:
    /// a key with no modifier but Shift is left out unless a rule took it or
    /// it is a function or navigation key, so what someone types cannot be
    /// read back from a report.
    var isWorthRecording: Bool {
        guard case .key(let combo) = trigger else { return true }
        if combo.isModifierAlone || !combo.modifiers.subtracting(.shift).isEmpty { return true }
        if rule != nil { return true }
        return combo.key.isFunctionOrNavigationKey
    }

    /// One line of the report, such as
    /// `14:20:11.123 ⌃W  keyboard: RK-KB5.0 (0x000e/0x3412)  app: com.apple.finder  → browser.closeTab: ⌘W`.
    ///
    /// Made in the event tap's callback while recording, so the time is put
    /// together from its parts rather than through a date formatter.
    func line(at date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let time = String(format: "%02d:%02d:%02d.%03d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
                          (parts.nanosecond ?? 0) / 1_000_000)
        return "\(time) \(Self.describe(trigger))  keyboard: \(keyboardDescription)"
            + "  app: \(frontmostBundleID ?? "none")  → \(result)"
    }

    private var keyboardDescription: String {
        switch keyboard {
        case .keyboard(let keyboard): keyboard.description
        case .unknown(let sender): "unknown (sender 0x\(String(sender, radix: 16)))"
        case .software: "none (posted by software)"
        case .lastModifier(let keyboard): "last modifier's, \(keyboard?.description ?? "not told")"
        }
    }

    private var result: String {
        guard let rule else { return "no match" }
        return "\(rule.id): \(Self.describe(rule.action))"
    }

    static func describe(_ trigger: Trigger) -> String {
        switch trigger {
        case .key(let combo):
            combo.caps(.mac).joined()
        case .mouseButton(let number, let modifiers):
            modifiers.caps(.mac).joined() + "button \(number)"
        case .scroll(let direction, let modifiers):
            modifiers.caps(.mac).joined() + "scroll \(direction.rawValue)"
        }
    }

    static func describe(_ action: Action) -> String {
        switch action {
        case .key(let combo): combo.caps(.mac).joined()
        case .openApplication(let bundleID): "open \(bundleID)"
        case .systemAction(let function): "system \(function.rawValue)"
        case .windowAction(let position): "window \(position.rawValue)"
        case .fileDialog(let action): "file dialog \(action.rawValue)"
        case .clipboardHistory: "clipboard history"
        }
    }
}

extension KeyCode {
    /// F1–F20, Esc, Home, End and the page keys: keys that type nothing.
    /// Arrows, Return, Tab and the erasing keys are left out, since in a run
    /// of them the shape of what was typed shows through.
    var isFunctionOrNavigationKey: Bool {
        Self.functionAndNavigation.contains(self)
    }

    private static let functionAndNavigation: Set<KeyCode> = Set([
        kVK_Escape, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ].map { KeyCode(rawValue: UInt16($0)) })
}
