import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@MainActor
@Suite struct RuleEditingTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "KeyBridgeTests-\(UUID().uuidString)")
    var store: ConfigurationStore { ConfigurationStore(fileURL: folder.appending(path: "config.json")) }

    final class Applied {
        var latest: [Rule] = []
    }

    func makeController(_ applied: Applied = Applied()) -> RulesController {
        RulesController(store: store) { [applied] in applied.latest = $0 }
    }

    func copyRule(_ controller: RulesController) throws -> Rule {
        try #require(controller.original(of: "edit.copy"))
    }

    @Test func anEditLandsInTheOverrideLayer() throws {
        let applied = Applied()
        let controller = makeController(applied)
        var copy = try copyRule(controller)
        copy.trigger = .key(combo: KeyCombo([.control, .shift], .c))
        controller.update(copy)

        #expect(controller.isCustomized("edit.copy"))
        #expect(!controller.isCustomized("edit.paste"))
        #expect(controller.configuration.overrides == [.modified(rule: copy)])
        #expect(controller.rules(inGroup: "editing").first == copy, "Shown in place of the preset's")
        #expect(applied.latest.first { $0.id == "edit.copy" } == copy, "The engine runs it")
        #expect(makeController().isCustomized("edit.copy"), "Saved to the file")
    }

    @Test func editingAgainReplacesTheOverride() throws {
        let controller = makeController()
        var copy = try copyRule(controller)
        copy.isEnabled = false
        controller.update(copy)
        copy.action = .key(combo: KeyCombo([.command, .shift], .c))
        controller.update(copy)
        #expect(controller.configuration.overrides == [.modified(rule: copy)])
    }

    @Test func editingBackToTheDefaultIsNotACustomization() throws {
        let controller = makeController()
        let original = try copyRule(controller)
        var copy = original
        copy.isEnabled = false
        controller.update(copy)
        controller.update(original)
        #expect(!controller.isCustomized("edit.copy"))
        #expect(controller.configuration.overrides.isEmpty)
    }

    @Test func resetBringsThePresetBack() throws {
        let controller = makeController()
        let original = try copyRule(controller)
        var copy = original
        copy.trigger = .key(combo: KeyCombo([.option], .c))
        controller.update(copy)
        controller.reset("edit.copy")
        #expect(!controller.isCustomized("edit.copy"))
        #expect(controller.effectiveRules.first == original)
    }

    @Test func customRulesAreLeftAloneByAReset() throws {
        let custom = Rule(id: "user.1", trigger: .key(combo: KeyCombo([.control], .q)),
                          action: .key(combo: KeyCombo([.command], .q)))
        try store.save(Configuration(overrides: [.custom(rule: custom)]))
        let controller = makeController()
        #expect(!controller.isCustomized("user.1"), "Customized marks changed preset entries")
        controller.reset("user.1")
        #expect(controller.configuration.overrides == [.custom(rule: custom)])
    }

    @Test func recordingPausesTheEngineAndResumesIt() throws {
        let applied = Applied()
        let controller = makeController(applied)
        controller.isRecording = true
        #expect(applied.latest.isEmpty, "Ctrl+C must reach the recorder as Ctrl+C")

        var copy = try copyRule(controller)
        copy.isEnabled = false
        controller.update(copy)
        #expect(applied.latest.isEmpty, "Still paused after a save")

        controller.isRecording = false
        #expect(applied.latest == controller.effectiveRules)
        #expect(applied.latest.first { $0.id == "edit.copy" }?.isEnabled == false)
    }

    @Test func aSharedTriggerIsReportedAsAConflict() throws {
        let controller = makeController()
        var copy = try copyRule(controller)
        #expect(controller.conflicts(with: copy).isEmpty)
        copy.trigger = .key(combo: KeyCombo([.control], .v))
        #expect(controller.conflicts(with: copy).map(\.id) == ["edit.paste"])
    }

    @Test func recordedPressesReadLikeTheEngine() {
        let ctrlShiftC = KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifierFlags: [.control, .shift, .capsLock])
        #expect(ctrlShiftC == KeyCombo([.control, .shift], .c), "Caps Lock is not a modifier")

        let home = KeyCombo(keyCode: UInt16(kVK_Home), modifierFlags: [.function])
        #expect(home == KeyCombo(.home), "fn comes with Home by itself")

        let fnS = KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifierFlags: [.function, .command])
        #expect(fnS == KeyCombo([.function, .command], .s))
    }
}
