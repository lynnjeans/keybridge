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
        // Back and forward in browsers and Finder. Not limited by app: the
        // side buttons mean nothing to a terminal either.
        Rule(id: "mouse.back", trigger: .mouseButton(number: 4),
             action: .key(combo: KeyCombo([.command], .leftBracket))),
        Rule(id: "mouse.forward", trigger: .mouseButton(number: 5),
             action: .key(combo: KeyCombo([.command], .rightBracket))),
        // Page zoom, like Ctrl+wheel on Windows. fn is the default modifier
        // because nothing else uses fn+scroll; Ctrl+scroll can be taken by
        // the system's screen zoom. ⌘= is what apps expect for ⌘+.
        Rule(id: "scroll.zoomIn", trigger: .scroll(direction: .up, modifiers: [.function]),
             action: .key(combo: KeyCombo([.command], .equal))),
        Rule(id: "scroll.zoomOut", trigger: .scroll(direction: .down, modifiers: [.function]),
             action: .key(combo: KeyCombo([.command], .minus))),
    ]

    private static func rule(_ id: String, _ from: KeyCombo, _ to: KeyCombo) -> Rule {
        Rule(
            id: id, trigger: .key(combo: from), action: .key(combo: to),
            scope: Scope(applications: .except(bundleIDs: terminals))
        )
    }
}
