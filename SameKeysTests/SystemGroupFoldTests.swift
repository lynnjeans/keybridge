import Foundation
import Testing

/// The System group went into Apps & System (SK-285).
@Suite struct SystemGroupFoldTests {
    private func decode(_ json: String) throws -> Configuration {
        try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
    }

    private func forceQuit(in configuration: Configuration) -> Rule? {
        configuration.presetRules(base: BuiltInRules.all).first { $0.id == "sys.forceQuit" }
    }

    @Test func forceQuitIsInAppsAndSystem() {
        let windows = BuiltInRules.preset.groups.first { $0.id == "windows" }
        #expect(windows?.rules.last?.id == "sys.forceQuit", "After Task Manager")
        #expect(!BuiltInRules.preset.groups.contains { $0.id == "system" })
    }

    @Test func aSwitchedOffSystemGroupKeepsForceQuitOff() throws {
        let configuration = try decode(#"{"schemaVersion": 1, "disabledGroups": ["system", "browser"]}"#)
        #expect(configuration.disabledGroups == ["browser"])
        #expect(forceQuit(in: configuration)?.isEnabled == false)
        #expect(configuration.isEnabled(group: try #require(BuiltInRules.preset.groups.first { $0.id == "windows" })))
    }

    @Test func aChangedForceQuitKeepsTheChangeAndIsSwitchedOff() throws {
        var changed = try #require(BuiltInRules.all.first { $0.id == "sys.forceQuit" })
        changed.trigger = .key(combo: KeyCombo([.control, .option], .delete))
        let overrides = String(decoding: try JSONEncoder().encode([Override.modified(rule: changed)]), as: UTF8.self)
        let configuration = try decode(#"{"schemaVersion": 1, "disabledGroups": ["system"], "overrides": \#(overrides)}"#)
        let rule = try #require(forceQuit(in: configuration))
        #expect(rule.trigger == changed.trigger)
        #expect(!rule.isEnabled)
        #expect(configuration.overrides.count == 1)
    }

    @Test func otherwiseNothingChanges() throws {
        let configuration = try decode(#"{"schemaVersion": 1, "disabledGroups": ["browser"]}"#)
        #expect(configuration.overrides.isEmpty)
        #expect(forceQuit(in: configuration)?.isEnabled == true)
    }
}
