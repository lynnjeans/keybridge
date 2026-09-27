/// Which Mac keys play Windows' Win and Alt (KB-226).
///
/// A PC keyboard's Win key reaches the Mac as ⌘ and its Alt key as ⌥, which
/// is how the preset is written. On a Mac keyboard the keys sit the other way
/// round: ⌥ where Win is, ⌘ where Alt is. Someone who presses by position,
/// as on their old keyboard, finds Win+L on ⌥L — and so does someone who
/// swapped the two keys in System Settings › Keyboard › Modifier Keys.
///
/// This is not a modifier remap: ⌘C stays ⌘C. It only decides which key the
/// preset's Win and Alt shortcuts are pressed with, as `ControlKey` does for
/// Ctrl, and what the two keys are called on the Windows side.
enum ModifierLayout: String, Codable, CaseIterable, Sendable {
    /// Win is ⌘ and Alt is ⌥, as a PC keyboard sends them. The preset as
    /// written.
    case pcKeyboard = "pc"
    /// Win is ⌥ and Alt is ⌘, where the keys sit on a Mac keyboard.
    case macPosition = "mac"

    /// Groups whose triggers stay as written in either layout. Window
    /// snapping is on ⌥ by position already, and ⌘+arrows would take line
    /// start and end (KB-201); it stays on ⌥ for everyone.
    static let fixedGroups: Set<String> = ["window"]

    /// A preset rule of `group` as pressed in this layout: ⌘ and ⌥ trade
    /// places in its key trigger. Mouse buttons and scrolling are left
    /// alone, as the fn setting leaves them.
    ///
    /// Trading places twice gives back the original, so the same call turns
    /// a trigger shown in this layout back into the preset's terms.
    func apply(to rule: Rule, inGroup group: String) -> Rule {
        guard self == .macPosition, !Self.fixedGroups.contains(group),
              case .key(let combo) = rule.trigger else { return rule }
        var swapped = rule
        swapped.trigger = .key(combo: Self.swap(combo))
        return swapped
    }

    func apply(to rules: [Rule], inGroup group: String) -> [Rule] {
        rules.map { apply(to: $0, inGroup: group) }
    }

    /// How triggers are spelled on the Windows side.
    var triggerStyle: KeyStyle {
        switch self {
        case .pcKeyboard: .windows
        case .macPosition: .windowsByPosition
        }
    }

    private static func swap(_ combo: KeyCombo) -> KeyCombo {
        var swapped = combo
        swapped.modifiers.remove([.command, .option])
        if combo.modifiers.contains(.command) { swapped.modifiers.insert(.option) }
        if combo.modifiers.contains(.option) { swapped.modifiers.insert(.command) }
        // Win alone (KB-224) is a trigger whose key is the modifier.
        if combo.key == .command { swapped.key = .option }
        if combo.key == .option { swapped.key = .command }
        return swapped
    }
}
