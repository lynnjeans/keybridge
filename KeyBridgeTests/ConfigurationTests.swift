import Foundation
import Testing

/// Every test works in its own temporary folder, never in the real
/// Application Support.
@Suite struct ConfigurationTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "KeyBridgeTests-\(UUID().uuidString)")
    var fileURL: URL { folder.appending(path: "config.json") }

    let copyOff: Override = {
        var rule = BuiltInRules.all.first { $0.id == "edit.copy" }!
        rule.isEnabled = false
        return .modified(rule: rule)
    }()
    let middleClickCloses = Override.custom(rule: Rule(
        id: "custom.1",
        trigger: .mouseButton(number: 3),
        action: .key(combo: KeyCombo([.command], .w))
    ))

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: fileURL)
    }

    func contents(of url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    /// The overrides as the JSON objects a file holds.
    func overridesJSON(_ overrides: [Override]) throws -> String {
        String(decoding: try JSONEncoder().encode(overrides), as: UTF8.self)
    }

    // MARK: - Loading and saving

    @Test func aFirstRunHasNoFileAndWritesNone() {
        let (configuration, outcome) = ConfigurationStore(fileURL: fileURL).load()
        #expect(outcome == .missing)
        #expect(configuration == Configuration())
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func aSavedConfigurationIsRestored() throws {
        let saved = Configuration(overrides: [copyOff, middleClickCloses])
        try ConfigurationStore(fileURL: fileURL).save(saved)

        // A new store, as after a restart.
        let (restored, outcome) = ConfigurationStore(fileURL: fileURL).load()
        #expect(outcome == .loaded)
        #expect(restored == saved)
    }

    @Test func theFileRecordsItsVersion() throws {
        try ConfigurationStore(fileURL: fileURL).save(Configuration(overrides: [copyOff]))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        #expect(object?["schemaVersion"] as? Int == Configuration.currentVersion)
        #expect((object?["overrides"] as? [Any])?.count == 1)
    }

    // MARK: - Migration

    /// A made-up version 0 that called the list "rules", upgraded by a
    /// made-up step: the real list of steps is still empty.
    @Test func anOlderFileIsMigratedAndTheOriginalKept() throws {
        let original = #"{"schemaVersion":0,"rules":\#(try overridesJSON([copyOff]))}"#
        try write(original)
        let store = ConfigurationStore(fileURL: fileURL, migrations: [
            0: { file in file["overrides"] = file.removeValue(forKey: "rules") },
        ])

        let (configuration, outcome) = store.load()
        #expect(outcome == .migrated(from: 0))
        #expect(configuration.overrides == [copyOff])
        #expect(try contents(of: folder.appending(path: "config.v0.json")) == original)

        // The upgraded file is written back, so the next launch just loads it.
        #expect(ConfigurationStore(fileURL: fileURL).load() == (configuration, .loaded))
    }

    @Test func anOlderFileWithNoWayUpIsSetAside() throws {
        try write(#"{"schemaVersion":0,"rules":[]}"#)
        let (configuration, outcome) = ConfigurationStore(fileURL: fileURL, migrations: [:]).load()
        guard case .unreadable(let backup) = outcome else {
            Issue.record("Expected the file to be set aside, got \(outcome)")
            return
        }
        #expect(configuration == Configuration())
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    // MARK: - Damaged and future files

    @Test func anUnreadableFileIsSetAsideAndTheDefaultsUsed() throws {
        try write("{ not json")
        let (configuration, outcome) = ConfigurationStore(fileURL: fileURL).load()
        guard case .unreadable(let backup) = outcome else {
            Issue.record("Expected the file to be set aside, got \(outcome)")
            return
        }
        #expect(configuration == Configuration())
        #expect(!FileManager.default.fileExists(atPath: fileURL.path), "The next save must not destroy it")
        #expect(try contents(of: backup) == "{ not json")
        #expect(backup.lastPathComponent.hasPrefix("config.unreadable-"))
    }

    @Test func aFileWithoutAVersionIsSetAside() throws {
        try write(#"{"overrides":[]}"#)
        let (_, outcome) = ConfigurationStore(fileURL: fileURL).load()
        guard case .unreadable = outcome else {
            Issue.record("Expected the file to be set aside, got \(outcome)")
            return
        }
    }

    @Test func aNewerFileIsReadButNeverOverwritten() throws {
        let future = #"{"schemaVersion":99,"overrides":\#(try overridesJSON([copyOff])),"somethingNew":true}"#
        try write(future)
        let store = ConfigurationStore(fileURL: fileURL)

        let (configuration, outcome) = store.load()
        #expect(outcome == .newer(version: 99))
        #expect(configuration.overrides == [copyOff], "What this build understands is used")
        #expect(throws: ConfigurationStore.StoreError.newerFileOnDisk(version: 99)) {
            try store.save(Configuration())
        }
        #expect(try contents(of: fileURL) == future)
    }

    // MARK: - Effective rules

    @Test func overridesApplyOnTopOfTheBuiltInRules() {
        let rules = Configuration(overrides: [copyOff, middleClickCloses]).effectiveRules(base: BuiltInRules.all)
        #expect(rules.map(\.id) == BuiltInRules.all.map(\.id) + ["custom.1"], "Order and priority are kept")
        // Evaluated outside #expect, whose expansion trips over closures and
        // optional chains here.
        let copyIsEnabled = rules.first { $0.id == "edit.copy" }?.isEnabled
        let othersAreEnabled = rules.filter { $0.id != "edit.copy" && $0.id != "custom.1" }.allSatisfy(\.isEnabled)
        #expect(copyIsEnabled == false)
        #expect(othersAreEnabled)
    }

    @Test func aModificationOfARuleNoLongerBuiltInIsIgnored() {
        var retired = BuiltInRules.all[0]
        retired.id = "edit.retired"
        let rules = Configuration(overrides: [.modified(rule: retired)]).effectiveRules(base: BuiltInRules.all)
        #expect(rules == BuiltInRules.all)
    }
}

// `load()` returns a tuple, which cannot conform to Equatable.
private func == (
    lhs: (configuration: Configuration, outcome: ConfigurationStore.Outcome),
    rhs: (configuration: Configuration, outcome: ConfigurationStore.Outcome)
) -> Bool {
    lhs.configuration == rhs.configuration && lhs.outcome == rhs.outcome
}
