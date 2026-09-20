/// The preset KeyBridge ships with: the Windows shortcut coverage list from
/// the market research, as switchable groups. The user's saved overrides
/// (`Configuration`) apply on top of it by rule ID, so IDs must never change.
///
/// Left out on purpose:
/// - Delete erasing forwards: a PC keyboard's Delete already does on a Mac.
/// - F1–F12 as standard function keys: an Apple keyboard's top row sends
///   media-key events, not F-key codes, so this is the system setting the
///   System group points to.
/// - Win alone opening Spotlight, and Win+V: they wait for lone-modifier
///   triggers and the clipboard history.
enum BuiltInRules {
    /// Terminals, where Ctrl combinations are control characters for the
    /// shell (Ctrl+C interrupts, Ctrl+W deletes a word) and must arrive
    /// unchanged.
    static let terminals = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
    ]

    static let finderID = "com.apple.finder"

    static let preset = Preset(id: "windows-standard", groups: [
        .init(id: "editing", rules: [
            outsideTerminals("edit.copy", KeyCombo([.control], .c), KeyCombo([.command], .c)),
            outsideTerminals("edit.cut", KeyCombo([.control], .x), KeyCombo([.command], .x)),
            outsideTerminals("edit.paste", KeyCombo([.control], .v), KeyCombo([.command], .v)),
            outsideTerminals("edit.undo", KeyCombo([.control], .z), KeyCombo([.command], .z)),
            outsideTerminals("edit.redo", KeyCombo([.control], .y), KeyCombo([.shift, .command], .z)),
            outsideTerminals("edit.selectAll", KeyCombo([.control], .a), KeyCombo([.command], .a)),
            outsideTerminals("edit.save", KeyCombo([.control], .s), KeyCombo([.command], .s)),
            outsideTerminals("edit.find", KeyCombo([.control], .f), KeyCombo([.command], .f)),
            outsideTerminals("edit.new", KeyCombo([.control], .n), KeyCombo([.command], .n)),
            outsideTerminals("edit.open", KeyCombo([.control], .o), KeyCombo([.command], .o)),
            outsideTerminals("edit.print", KeyCombo([.control], .p), KeyCombo([.command], .p)),
        ]),
        .init(id: "navigation", rules: [
            outsideTerminals("nav.lineStart", KeyCombo(.home), KeyCombo([.command], .leftArrow)),
            outsideTerminals("nav.lineEnd", KeyCombo(.end), KeyCombo([.command], .rightArrow)),
            outsideTerminals("nav.selectLineStart", KeyCombo([.shift], .home), KeyCombo([.shift, .command], .leftArrow)),
            outsideTerminals("nav.selectLineEnd", KeyCombo([.shift], .end), KeyCombo([.shift, .command], .rightArrow)),
            outsideTerminals("nav.docStart", KeyCombo([.control], .home), KeyCombo([.command], .upArrow)),
            outsideTerminals("nav.docEnd", KeyCombo([.control], .end), KeyCombo([.command], .downArrow)),
            outsideTerminals("nav.selectDocStart", KeyCombo([.control, .shift], .home), KeyCombo([.shift, .command], .upArrow)),
            outsideTerminals("nav.selectDocEnd", KeyCombo([.control, .shift], .end), KeyCombo([.shift, .command], .downArrow)),
            outsideTerminals("nav.wordLeft", KeyCombo([.control], .leftArrow), KeyCombo([.option], .leftArrow)),
            outsideTerminals("nav.wordRight", KeyCombo([.control], .rightArrow), KeyCombo([.option], .rightArrow)),
            outsideTerminals("nav.selectWordLeft", KeyCombo([.control, .shift], .leftArrow), KeyCombo([.shift, .option], .leftArrow)),
            outsideTerminals("nav.selectWordRight", KeyCombo([.control, .shift], .rightArrow), KeyCombo([.shift, .option], .rightArrow)),
            outsideTerminals("nav.deleteWord", KeyCombo([.control], .delete), KeyCombo([.option], .delete)),
        ]),
        // Only in Finder, and never while renaming or searching: there Enter,
        // Backspace and Ctrl+V have to do what they do in any text field.
        .init(id: "finder", rules: [
            inFinder("finder.trash", KeyCombo(.forwardDelete), KeyCombo([.command], .delete)),
            inFinder("finder.rename", KeyCombo(.f2), KeyCombo(.returnKey)),
            inFinder("finder.open", KeyCombo(.returnKey), KeyCombo([.command], .downArrow)),
            // Ctrl+X marks for moving: Finder has no cut, but ⌘C followed by
            // ⌥⌘V moves the files.
            inFinder("finder.cut", KeyCombo([.control], .x), KeyCombo([.command], .c)),
            inFinder("finder.move", KeyCombo([.control], .v), KeyCombo([.option, .command], .v)),
            inFinder("finder.parent", KeyCombo(.delete), KeyCombo([.command], .upArrow)),
        ]),
        .init(id: "windows", rules: [
            rule("win.switchApp", KeyCombo([.option], .tab), KeyCombo([.command], .tab)),
            rule("win.quit", KeyCombo([.option], .f4), KeyCombo([.command], .q)),
            // PC keyboards send Print Screen as F13. As on Windows, the
            // screenshot goes to the clipboard (⌃ added), not to a file, so
            // it also lands in the clipboard history.
            rule("win.screenshot", KeyCombo(.f13), KeyCombo([.control, .shift, .command], .three)),
            Rule(id: "win.taskManager", trigger: .key(combo: KeyCombo([.control, .shift], .escape)),
                 action: .openApplication(bundleID: "com.apple.ActivityMonitor")),
        ]),
        .init(id: "browser", rules: [
            outsideTerminals("browser.newTab", KeyCombo([.control], .t), KeyCombo([.command], .t)),
            outsideTerminals("browser.closeTab", KeyCombo([.control], .w), KeyCombo([.command], .w)),
            outsideTerminals("browser.reopenTab", KeyCombo([.control, .shift], .t), KeyCombo([.shift, .command], .t)),
            outsideTerminals("browser.address", KeyCombo([.control], .l), KeyCombo([.command], .l)),
            outsideTerminals("browser.reload", KeyCombo([.control], .r), KeyCombo([.command], .r)),
        ]),
        .init(id: "system", rules: [
            rule("sys.forceQuit", KeyCombo([.control, .option], .forwardDelete), KeyCombo([.option, .command], .escape)),
        ]),
        // A PC keyboard's Win key arrives as ⌘, so these also take over ⌘L,
        // ⌘E, ⌘D, ⌘. and ⌘⇧S on a Mac keyboard. Off until the user asks, and
        // limited to one keyboard once devices can be told apart.
        .init(id: "winKey", rules: [
            rule("winKey.lock", KeyCombo([.command], .l), KeyCombo([.control, .command], .q)),
            Rule(id: "winKey.explorer", trigger: .key(combo: KeyCombo([.command], .e)),
                 action: .openApplication(bundleID: finderID)),
            // Whatever Show Desktop is set to (F11 as shipped), so a changed
            // shortcut keeps working.
            Rule(id: "winKey.showDesktop", trigger: .key(combo: KeyCombo([.command], .d)),
                 action: .systemAction(.showDesktop)),
            rule("winKey.emoji", KeyCombo([.command], .period), KeyCombo([.control, .command], .space)),
            rule("winKey.screenshotArea", KeyCombo([.shift, .command], .s), KeyCombo([.control, .shift, .command], .four)),
        ], isEnabledByDefault: false),
        // Win+←/→/↑ on Windows. The trigger is ⌥, not ⌘, because these are
        // arrow keys pressed by feel: on a Mac keyboard ⌥ sits where the Win
        // key sits on a PC one, and ⌘ where Alt does. ⌥+arrow is macOS's own
        // move-by-word, but the people this preset is for reach for Ctrl+←
        // instead — the navigation group turns that into ⌥← for them, and
        // KeyBridge's own output is stamped, so it never comes back through
        // here as a snap.
        .init(id: "window", rules: [
            Rule(id: "window.leftHalf", trigger: .key(combo: KeyCombo([.option], .leftArrow)),
                 action: .windowSnap(.leftHalf)),
            Rule(id: "window.rightHalf", trigger: .key(combo: KeyCombo([.option], .rightArrow)),
                 action: .windowSnap(.rightHalf)),
            Rule(id: "window.maximize", trigger: .key(combo: KeyCombo([.option], .upArrow)),
                 action: .windowSnap(.maximize)),
        ]),
        .init(id: "mouse", rules: [
            // Back and forward in browsers and Finder. Not limited by app: the
            // side buttons mean nothing to a terminal either.
            Rule(id: "mouse.back", trigger: .mouseButton(number: 4),
                 action: .key(combo: KeyCombo([.command], .leftBracket))),
            Rule(id: "mouse.forward", trigger: .mouseButton(number: 5),
                 action: .key(combo: KeyCombo([.command], .rightBracket))),
        ]),
        .init(id: "scroll", rules: [
            // Page zoom, like Ctrl+wheel on Windows. fn is the default modifier
            // because nothing else uses fn+scroll; Ctrl+scroll can be taken by
            // the system's screen zoom. ⌘= is what apps expect for ⌘+.
            Rule(id: "scroll.zoomIn", trigger: .scroll(direction: .up, modifiers: [.function]),
                 action: .key(combo: KeyCombo([.command], .equal))),
            Rule(id: "scroll.zoomOut", trigger: .scroll(direction: .down, modifiers: [.function]),
                 action: .key(combo: KeyCombo([.command], .minus))),
        ]),
    ])

    /// Every rule of the preset, including groups that start off.
    static var all: [Rule] { preset.rules }

    private static func rule(_ id: String, _ from: KeyCombo, _ to: KeyCombo, scope: Scope = .everywhere) -> Rule {
        Rule(id: id, trigger: .key(combo: from), action: .key(combo: to), scope: scope)
    }

    private static func outsideTerminals(_ id: String, _ from: KeyCombo, _ to: KeyCombo) -> Rule {
        rule(id, from, to, scope: Scope(applications: .except(bundleIDs: terminals)))
    }

    private static func inFinder(_ id: String, _ from: KeyCombo, _ to: KeyCombo) -> Rule {
        rule(id, from, to, scope: Scope(applications: .only(bundleIDs: [finderID]), skipsTextInput: true))
    }
}
