import Foundation
import Testing

@MainActor
@Suite struct CustomRuleTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "KeyBridgeTests-\(UUID().uuidString)")
    var store: ConfigurationStore { ConfigurationStore(fileURL: folder.appending(path: "config.json")) }

    final class Applied { var latest: [Rule] = [] }

    let fnCopy = Rule(id: "custom.1", trigger: .key(combo: KeyCombo([.function], .c)),
                      action: .key(combo: KeyCombo([.command], .c)), name: "Copy with fn")

    func matched(_ rules: [Rule], _ combo: KeyCombo, in app: String = "com.apple.TextEdit") -> String? {
        RuleMatcher(rules: rules).match(.key(combo: combo), in: MatchContext(frontmostBundleID: app))?.id
    }

    @Test func aRuleIsCreatedEditedAndDeletedAtOnce() {
        let applied = Applied()
        let controller = RulesController(store: store, apply: { [applied] in applied.latest = $0 })

        controller.saveCustomRule(fnCopy)
        #expect(controller.customRules == [fnCopy])
        #expect(matched(applied.latest, KeyCombo([.function], .c)) == "custom.1", "In effect at once")
        #expect(matched(applied.latest, KeyCombo([.control], .c)) == "edit.copy", "Next to Ctrl+C, not instead")

        var edited = fnCopy
        edited.trigger = .mouseButton(number: 3)
        controller.saveCustomRule(edited)
        #expect(controller.customRules == [edited], "Replaced in place, not added")
        #expect(RulesController(store: store).customRules == [edited], "Saved")

        controller.deleteCustomRule("custom.1")
        #expect(controller.customRules.isEmpty)
        #expect(!applied.latest.contains { $0.id == "custom.1" })
    }

    @Test func theUsersRuleWinsOverThePresetsOnTheSameShortcut() {
        let controller = RulesController(store: store)
        let quit = Rule(id: "custom.2", trigger: .key(combo: KeyCombo([.option], .f4)),
                        action: .key(combo: KeyCombo([.command], .w)))
        controller.saveCustomRule(quit)
        #expect(matched(controller.effectiveRules, KeyCombo([.option], .f4)) == "custom.2")
    }

    @Test func customRulesAreNotListedUnderPresetGroups() {
        let controller = RulesController(store: store)
        controller.saveCustomRule(fnCopy)
        for group in BuiltInRules.preset.groups {
            #expect(!controller.rules(inGroup: group.id).contains { $0.id == "custom.1" }, "\(group.id)")
        }
        #expect(controller.customizedCount == 0, "Customized counts changed preset entries")
    }

    @Test func theControlKeyLeavesCustomRulesAsRecorded() {
        let controller = RulesController(store: store)
        let ctrlQ = Rule(id: "custom.3", trigger: .key(combo: KeyCombo([.control], .q)),
                         action: .key(combo: KeyCombo([.command], .q)))
        controller.saveCustomRule(ctrlQ)
        controller.setControlKey(.function)
        #expect(controller.effectiveRules.contains(ctrlQ))
        #expect(!controller.effectiveRules.contains { $0.id == "custom.3.fn" })
    }

    @Test func aNameIsSavedAndLeftOutWhenAbsent() throws {
        let data = try JSONEncoder().encode(fnCopy)
        #expect(try JSONDecoder().decode(Rule.self, from: data) == fnCopy)
        var unnamed = fnCopy
        unnamed.name = nil
        #expect(!String(decoding: try JSONEncoder().encode(unnamed), as: UTF8.self).contains("name"))
    }
}
