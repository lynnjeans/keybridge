import Foundation
import Testing

@Suite struct RuleModelTests {
    @Test func coverageListRoundTrips() throws {
        let preset = CoverageList.preset
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        #expect(decoded == preset)
    }

    @Test func overridesRoundTrip() throws {
        let copy = try #require(CoverageList.preset.rules.first { $0.id == "edit.copy" })
        var disabledCopy = copy
        disabledCopy.isEnabled = false
        let overrides: [Override] = [
            .modified(rule: disabledCopy),
            .custom(rule: Rule(
                id: "custom.1",
                trigger: .mouseButton(number: 3, modifiers: [.shift]),
                action: .key(combo: KeyCombo([.command], .w))
            )),
        ]
        let data = try JSONEncoder().encode(overrides)
        #expect(try JSONDecoder().decode([Override].self, from: data) == overrides)
    }

    @Test func coverageListHasNoDuplicateIDs() {
        let ids = CoverageList.preset.rules.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// The encoded form is the configuration file format, so changing it needs
    /// a schema migration. This test makes such a change visible.
    @Test func ruleEncodingIsStable() throws {
        let rule = Rule(
            id: "edit.copy",
            trigger: .key(combo: KeyCombo([.control], .c)),
            action: .key(combo: KeyCombo([.command], .c)),
            scope: Scope(applications: .except(bundleIDs: ["com.apple.Terminal"]))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(rule), as: UTF8.self)
        #expect(json == """
            {"action":{"key":{"combo":{"key":8,"modifiers":["command"]}}},\
            "id":"edit.copy","isEnabled":true,\
            "scope":{"applications":{"except":{"bundleIDs":["com.apple.Terminal"]}},"devices":{"all":{}}},\
            "trigger":{"key":{"combo":{"key":8,"modifiers":["control"]}}}}
            """)
    }

    @Test func modifiersEncodeAsNamesInCanonicalOrder() throws {
        let json = try JSONEncoder().encode(Modifiers([.function, .shift, .control]))
        #expect(String(decoding: json, as: UTF8.self) == #"["control","shift","fn"]"#)
    }

    @Test func unknownModifierIsRejected() {
        let json = Data(#"["control","hyper"]"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Modifiers.self, from: json)
        }
    }
}

/// Every entry of the Windows shortcut coverage list, written as rules. This
/// is the proof that the model can express the preset packs; the shipped
/// presets themselves arrive with KB-060 and may choose differently where the
/// list offers alternatives.
enum CoverageList {
    static let terminals = ["com.apple.Terminal", "com.googlecode.iterm2"]
    static let finder = Scope(applications: .only(bundleIDs: ["com.apple.finder"]))
    /// Win-key shortcuts only make sense on a PC keyboard, whose Win key
    /// arrives as ⌘. An arbitrary example device stands in for it here.
    static let pcKeyboard = Scope(devices: .only(devices: [DeviceID(vendorID: 0x046D, productID: 0xC31C)]))

    static func rule(
        _ id: String, _ from: KeyCombo, _ to: KeyCombo, scope: Scope = .everywhere
    ) -> Rule {
        Rule(id: id, trigger: .key(combo: from), action: .key(combo: to), scope: scope)
    }

    static let preset = Preset(id: "windows-standard", groups: [
        .init(id: "editing", rules: [
            rule("edit.copy", KeyCombo([.control], .c), KeyCombo([.command], .c),
                 scope: Scope(applications: .except(bundleIDs: terminals))),
            rule("edit.cut", KeyCombo([.control], .x), KeyCombo([.command], .x)),
            rule("edit.paste", KeyCombo([.control], .v), KeyCombo([.command], .v)),
            rule("edit.undo", KeyCombo([.control], .z), KeyCombo([.command], .z)),
            rule("edit.redo", KeyCombo([.control], .y), KeyCombo([.shift, .command], .z)),
            rule("edit.selectAll", KeyCombo([.control], .a), KeyCombo([.command], .a)),
            rule("edit.save", KeyCombo([.control], .s), KeyCombo([.command], .s)),
            rule("edit.find", KeyCombo([.control], .f), KeyCombo([.command], .f)),
            rule("edit.new", KeyCombo([.control], .n), KeyCombo([.command], .n)),
            rule("edit.open", KeyCombo([.control], .o), KeyCombo([.command], .o)),
            rule("edit.print", KeyCombo([.control], .p), KeyCombo([.command], .p)),
            // Alternative trigger from the design spec: fn+C on a Mac keyboard.
            rule("edit.copy.fn", KeyCombo([.function], .c), KeyCombo([.command], .c)),
        ]),
        .init(id: "navigation", rules: [
            rule("nav.lineStart", KeyCombo(.home), KeyCombo([.command], .leftArrow)),
            rule("nav.lineEnd", KeyCombo(.end), KeyCombo([.command], .rightArrow)),
            rule("nav.docStart", KeyCombo([.control], .home), KeyCombo([.command], .upArrow)),
            rule("nav.docEnd", KeyCombo([.control], .end), KeyCombo([.command], .downArrow)),
            rule("nav.wordLeft", KeyCombo([.control], .leftArrow), KeyCombo([.option], .leftArrow)),
            rule("nav.wordRight", KeyCombo([.control], .rightArrow), KeyCombo([.option], .rightArrow)),
            rule("nav.selectLineStart", KeyCombo([.shift], .home), KeyCombo([.shift, .command], .leftArrow)),
            rule("nav.selectLineEnd", KeyCombo([.shift], .end), KeyCombo([.shift, .command], .rightArrow)),
            rule("nav.deleteForward", KeyCombo(.forwardDelete), KeyCombo([.function], .delete)),
            rule("nav.deleteWord", KeyCombo([.control], .delete), KeyCombo([.option], .delete)),
        ]),
        .init(id: "finder", rules: [
            rule("finder.trash", KeyCombo(.forwardDelete), KeyCombo([.command], .delete), scope: finder),
            rule("finder.rename", KeyCombo(.f2), KeyCombo(.returnKey), scope: finder),
            rule("finder.open", KeyCombo(.returnKey), KeyCombo([.command], .downArrow), scope: finder),
            rule("finder.cut", KeyCombo([.control], .x), KeyCombo([.command], .c), scope: finder),
            rule("finder.move", KeyCombo([.control], .v), KeyCombo([.option, .command], .v), scope: finder),
            rule("finder.parent", KeyCombo(.delete), KeyCombo([.command], .upArrow), scope: finder),
        ]),
        .init(id: "windows", rules: [
            rule("win.switchApp", KeyCombo([.option], .tab), KeyCombo([.command], .tab)),
            rule("win.quit", KeyCombo([.option], .f4), KeyCombo([.command], .q)),
            rule("win.lock", KeyCombo([.command], .l), KeyCombo([.control, .command], .q), scope: pcKeyboard),
            rule("win.screenshot", KeyCombo(.f13), KeyCombo([.shift, .command], .three)),
            Rule(id: "win.taskManager", trigger: .key(combo: KeyCombo([.control, .shift], .escape)),
                 action: .openApplication(bundleID: "com.apple.ActivityMonitor")),
            Rule(id: "win.explorer", trigger: .key(combo: KeyCombo([.command], .e)),
                 action: .openApplication(bundleID: "com.apple.finder"), scope: pcKeyboard),
            rule("win.showDesktop", KeyCombo([.command], .d), KeyCombo(.f11), scope: pcKeyboard),
        ]),
        .init(id: "browser", rules: [
            rule("browser.newTab", KeyCombo([.control], .t), KeyCombo([.command], .t)),
            rule("browser.closeTab", KeyCombo([.control], .w), KeyCombo([.command], .w)),
            rule("browser.reopenTab", KeyCombo([.control, .shift], .t), KeyCombo([.shift, .command], .t)),
            rule("browser.address", KeyCombo([.control], .l), KeyCombo([.command], .l)),
            rule("browser.reload", KeyCombo([.control], .r), KeyCombo([.command], .r)),
            Rule(id: "browser.back", trigger: .mouseButton(number: 4),
                 action: .key(combo: KeyCombo([.command], .leftBracket))),
            Rule(id: "browser.forward", trigger: .mouseButton(number: 5),
                 action: .key(combo: KeyCombo([.command], .rightBracket))),
            Rule(id: "browser.zoomIn", trigger: .scroll(direction: .up, modifiers: [.function]),
                 action: .key(combo: KeyCombo([.command], .equal))),
            Rule(id: "browser.zoomOut", trigger: .scroll(direction: .down, modifiers: [.function]),
                 action: .key(combo: KeyCombo([.command], .minus))),
        ]),
        .init(id: "system", rules: [
            // F1–F12 as standard function keys: one rule per key, F1 shown.
            rule("sys.f1", KeyCombo(.f1), KeyCombo([.function], .f1)),
            rule("sys.emoji", KeyCombo([.command], .period), KeyCombo([.control, .command], .space),
                 scope: pcKeyboard),
            rule("sys.screenshotArea", KeyCombo([.command, .shift], .s), KeyCombo([.shift, .command], .four),
                 scope: pcKeyboard),
            rule("sys.clipboard", KeyCombo([.command], .v), KeyCombo([.shift, .command], .v),
                 scope: pcKeyboard),
            rule("sys.spotlight", KeyCombo(.command), KeyCombo([.command], .space), scope: pcKeyboard),
            rule("sys.forceQuit", KeyCombo([.control, .option], .forwardDelete),
                 KeyCombo([.option, .command], .escape)),
        ]),
    ])
}
