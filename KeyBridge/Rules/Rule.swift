// Enum cases in this folder label their associated values: synthesized Codable
// writes unlabeled ones as "_0", which would leak into the configuration file.

/// One mapping: when `trigger` happens within `scope`, perform `action`
/// instead.
struct Rule: Codable, Hashable, Identifiable, Sendable {
    /// Stable across releases for preset rules (for example `edit.copy`), so a
    /// user's override keeps pointing at the same entry when the preset is
    /// updated.
    var id: String
    var trigger: Trigger
    var action: Action
    var scope: Scope = .everywhere
    var isEnabled = true
}

/// The input a rule reacts to.
enum Trigger: Codable, Hashable, Sendable {
    /// A key combination, such as ⌃C or Home.
    case key(combo: KeyCombo)
    /// A mouse button beyond the primary and secondary buttons, numbered the
    /// way users see it: 3 is the middle button, 4 and 5 are the side buttons.
    case mouseButton(number: Int, modifiers: Modifiers = [])
    /// Scrolling in one direction while holding `modifiers`.
    case scroll(direction: ScrollDirection, modifiers: Modifiers)
}

enum ScrollDirection: String, Codable, Hashable, Sendable {
    case up, down, left, right
}

/// What a rule does in place of its trigger.
enum Action: Codable, Hashable, Sendable {
    /// Posts a key combination, such as ⌘C.
    case key(combo: KeyCombo)
    /// Launches or activates an application. Covers Windows shortcuts with no
    /// macOS key equivalent, such as Win+E opening Finder.
    case openApplication(bundleID: String)
}
