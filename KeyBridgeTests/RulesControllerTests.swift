import Foundation
import Testing

@MainActor
@Suite struct RulesControllerTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "KeyBridgeTests-\(UUID().uuidString)")
    var store: ConfigurationStore { ConfigurationStore(fileURL: folder.appending(path: "config.json")) }

    /// The rules handed to the engine, newest last.
    final class Applied {
        var sets: [[Rule]] = []
        var latest: [Rule] { sets.last ?? [] }
    }

    func makeController(_ applied: Applied) -> RulesController {
        RulesController(store: store, apply: { [applied] in applied.sets.append($0) })
    }

    /// The rules of every group that starts on.
    var defaultRules: [Rule] {
        BuiltInRules.preset.groups.filter(\.isEnabledByDefault).flatMap(\.rules)
    }

    @Test func groupsStartAtTheirDefaults() {
        let applied = Applied()
        let controller = makeController(applied)
        #expect(controller.effectiveRules.map(\.id) == defaultRules.map(\.id))
        #expect(applied.latest.count == defaultRules.count, "The engine gets them at once")
        for group in BuiltInRules.preset.groups {
            #expect(controller.isEnabled(group: group.id) == group.isEnabledByDefault)
        }
        #expect(!controller.isEnabled(group: "winKey"), "Would take over ⌘ shortcuts on a Mac keyboard")
    }

    @Test func aGroupThatStartsOffCanBeSwitchedOn() {
        let controller = makeController(Applied())
        controller.setGroup("winKey", enabled: true)
        #expect(controller.effectiveRules.contains { $0.id == "winKey.lock" })
        #expect(controller.configuration.enabledGroups == ["winKey"])
        #expect(makeController(Applied()).isEnabled(group: "winKey"), "Saved")

        controller.setGroup("winKey", enabled: false)
        #expect(controller.configuration.enabledGroups.isEmpty, "Back at the default, nothing to remember")
        #expect(controller.configuration.disabledGroups.isEmpty)
    }

    @Test func anOlderFileWithoutEnabledGroupsStillLoads() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"schemaVersion": 1, "overrides": [], "disabledGroups": ["mouse"]}"#
        try Data(json.utf8).write(to: store.fileURL)
        let controller = makeController(Applied())
        #expect(!controller.isEnabled(group: "mouse"))
        #expect(!controller.isEnabled(group: "winKey"))
        #expect(controller.isEnabled(group: "editing"))
    }

    @Test func switchingAGroupOffTakesItOutOfEffect() {
        let applied = Applied()
        let controller = makeController(applied)
        controller.setGroup("editing", enabled: false)

        #expect(!controller.isEnabled(group: "editing"))
        #expect(!controller.effectiveRules.contains { $0.id.hasPrefix("edit.") })
        #expect(controller.effectiveRules.contains { $0.id == "nav.lineStart" }, "Other groups stay")
        #expect(applied.latest.map(\.id) == controller.effectiveRules.map(\.id), "The engine is told")
    }

    @Test func aSwitchedOffGroupStillListsItsEntries() {
        let controller = makeController(Applied())
        controller.setGroup("mouse", enabled: false)
        #expect(controller.rules(inGroup: "mouse").count == 2, "Shown greyed out, not hidden")
    }

    @Test func theChoiceSurvivesARestart() {
        let controller = makeController(Applied())
        controller.setGroup("scroll", enabled: false)

        // A second controller, as after a relaunch, reading the same file.
        let restarted = makeController(Applied())
        #expect(!restarted.isEnabled(group: "scroll"))
        #expect(!restarted.effectiveRules.contains { $0.id.hasPrefix("scroll.") })
    }

    @Test func switchingAGroupBackOnRestoresIt() {
        let controller = makeController(Applied())
        controller.setGroup("editing", enabled: false)
        controller.setGroup("editing", enabled: true)
        #expect(controller.effectiveRules.map(\.id) == defaultRules.map(\.id))
        #expect(controller.configuration.disabledGroups.isEmpty)
    }

    @Test func groupStateIsWrittenInAStableOrder() throws {
        let controller = makeController(Applied())
        controller.setGroup("scroll", enabled: false)
        controller.setGroup("editing", enabled: false)
        let json = String(decoding: try Data(contentsOf: store.fileURL), as: UTF8.self)
        #expect(json.contains(#""disabledGroups" : ["#))
        let editing = try #require(json.range(of: "editing"))
        let scroll = try #require(json.range(of: "scroll"))
        #expect(editing.lowerBound < scroll.lowerBound, "Sorted, so the file does not churn")
    }

    @Test func anOverriddenEntryStillShowsUnderItsGroup() {
        var copy = try! #require(BuiltInRules.all.first { $0.id == "edit.copy" })
        copy.isEnabled = false
        let store = self.store
        try! store.save(Configuration(overrides: [.modified(rule: copy)]))

        let controller = RulesController(store: store)
        let editing = controller.rules(inGroup: "editing")
        #expect(editing.first { $0.id == "edit.copy" }?.isEnabled == false)
    }

    @Test func overviewCountsFollowTheConfiguration() throws {
        let controller = makeController(Applied())
        #expect(controller.activeRuleCount == defaultRules.count)
        #expect(controller.customizedCount == 0)
        #expect(controller.exceptionApps == Set(BuiltInRules.terminals))

        var copy = try #require(controller.original(of: "edit.copy"))
        copy.isEnabled = false
        controller.update(copy)
        #expect(controller.activeRuleCount == defaultRules.count - 1, "A switched-off entry is not active")
        #expect(controller.customizedCount == 1)

        controller.setControlKey(.function)
        #expect(controller.effectiveRules.first { $0.id == "edit.paste.fn" }?.scope.applications == .all,
                "fn shortcuts apply in terminals too")
        #expect(controller.exceptionApps == Set(BuiltInRules.terminals), "Home and End still skip them")
    }
}
