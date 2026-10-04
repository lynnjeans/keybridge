import Foundation
import Testing

/// How the user's layer meets the preset where the two decisions disagree:
/// an edited entry in a switched-off group, a group that starts off, the
/// Ctrl key choice as shown, and a file that cannot be written.
extension ConfigurationTests {
    /// Copy moved to Ctrl+Shift+C, as terminals on Linux have it.
    var copyOnCtrlShiftC: Override {
        var rule = BuiltInRules.all.first { $0.id == "edit.copy" }!
        rule.trigger = .key(combo: KeyCombo([.control, .shift], .c))
        return .modified(rule: rule)
    }

    @Test func anEditedEntryOfASwitchedOffGroupStaysOff() {
        var configuration = Configuration(overrides: [copyOnCtrlShiftC])
        let editing = BuiltInRules.preset.groups.first { $0.id == "editing" }!
        configuration.setGroup(editing, enabled: false)
        let ids = configuration.effectiveRules(of: BuiltInRules.preset).map(\.id)
        #expect(!ids.contains("edit.copy"), "The group switch is the broader decision")
        #expect(!ids.contains("edit.paste"))

        configuration.setGroup(editing, enabled: true)
        let copy = configuration.effectiveRules(of: BuiltInRules.preset).first { $0.id == "edit.copy" }
        #expect(copy?.trigger == .key(combo: KeyCombo([.control, .shift], .c)), "Switching back on brings the edit back")
    }

    @Test func aGroupThatStartsOffComesInWithItsEdits() {
        var lock = BuiltInRules.all.first { $0.id == "winKey.lock" }!
        lock.isEnabled = false
        var configuration = Configuration(overrides: [.modified(rule: lock)])
        let winKey = BuiltInRules.preset.groups.first { $0.id == "winKey" }!
        #expect(!configuration.effectiveRules(of: BuiltInRules.preset).contains { $0.id.hasPrefix("winKey.") })

        configuration.setGroup(winKey, enabled: true)
        let rules = configuration.effectiveRules(of: BuiltInRules.preset)
        let lockIsEnabled = rules.first { $0.id == "winKey.lock" }?.isEnabled
        #expect(lockIsEnabled == false, "The entry the user switched off stays off")
        #expect(rules.contains { $0.id == "winKey.explorer" && $0.isEnabled })
    }

    @Test func anOverrideIsKnownByItsRulesID() {
        #expect(copyOnCtrlShiftC.id == "edit.copy")
        #expect(middleClickCloses.id == "custom.1")
        #expect(middleClickCloses.rule.action == .key(combo: KeyCombo([.command], .w)))
    }
}

extension ControlKeyTests {
    @Test func entriesShowTheKeyTheyArePressedWith() {
        let copy = BuiltInRules.all.first { $0.id == "edit.copy" }!
        let wordLeft = BuiltInRules.all.first { $0.id == "nav.wordLeft" }!
        let back = BuiltInRules.all.first { $0.id == "mouse.back" }!

        #expect(ControlKey.function.trigger(of: copy) == .key(combo: KeyCombo([.function], .c)))
        #expect(ControlKey.control.trigger(of: copy) == copy.trigger)
        #expect(ControlKey.both.trigger(of: copy) == copy.trigger, "Both lists the Ctrl form")
        #expect(ControlKey.function.trigger(of: wordLeft) == wordLeft.trigger, "fn+← is Home, so arrows keep Ctrl")
        #expect(ControlKey.function.trigger(of: back) == back.trigger)
    }
}

extension RulesControllerTests {
    @Test func aChangeTakesEffectEvenWhenTheFileCannotBeWritten() throws {
        // A file where the folder should be, so saving fails.
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }

        let applied = Applied()
        let controller = makeController(applied)
        controller.setGroup("editing", enabled: false)
        #expect(!applied.latest.contains { $0.id == "edit.copy" }, "The engine follows the change")
        #expect(!controller.isEnabled(group: "editing"))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "config.json").path))
    }
}
