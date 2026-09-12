/// The rules KeyBridge runs with until presets (KB-060) and saved
/// configuration (KB-032) exist: the editing and line-navigation basics of the
/// walking skeleton.
enum BuiltInRules {
    /// Terminals, where Ctrl combinations are control characters for the
    /// shell (Ctrl+C interrupts, Ctrl+Z suspends) and must arrive unchanged.
    static let terminals = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
    ]

    static let all: [Rule] = [
        rule("edit.copy", KeyCombo([.control], .c), KeyCombo([.command], .c)),
        rule("edit.cut", KeyCombo([.control], .x), KeyCombo([.command], .x)),
        rule("edit.paste", KeyCombo([.control], .v), KeyCombo([.command], .v)),
        rule("edit.undo", KeyCombo([.control], .z), KeyCombo([.command], .z)),
        rule("nav.lineStart", KeyCombo(.home), KeyCombo([.command], .leftArrow)),
        rule("nav.lineEnd", KeyCombo(.end), KeyCombo([.command], .rightArrow)),
        rule("nav.selectLineStart", KeyCombo([.shift], .home), KeyCombo([.shift, .command], .leftArrow)),
        rule("nav.selectLineEnd", KeyCombo([.shift], .end), KeyCombo([.shift, .command], .rightArrow)),
    ]

    private static func rule(_ id: String, _ from: KeyCombo, _ to: KeyCombo) -> Rule {
        Rule(
            id: id, trigger: .key(combo: from), action: .key(combo: to),
            scope: Scope(applications: .except(bundleIDs: terminals))
        )
    }
}
