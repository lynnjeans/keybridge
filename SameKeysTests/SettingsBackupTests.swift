import Foundation
import Testing

/// Exporting and importing settings (SK-270).
@Suite struct SettingsBackupTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "SettingsBackupTests-\(UUID().uuidString)")
    private var configurationFile: URL { folder.appending(path: "config.json") }

    private func freshDefaults() -> UserDefaults {
        let suite = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func writeConfiguration(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(configuration).write(to: configurationFile)
    }

    private func readConfiguration() throws -> Configuration {
        try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configurationFile))
    }

    @Test func aBackupRestoresTheSettingsItWasMadeFrom() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        var configuration = Configuration()
        configuration.disabledGroups = ["browser"]
        configuration.enabledGroups = ["winKey"]
        configuration.wheelDirection = .windows
        configuration.dockClickMinimizes = false
        try writeConfiguration(configuration)
        let hotKey = try JSONEncoder().encode(KeyCombo([.option], .v))
        let preferences: [String: Any] = [
            "clipboard.enabled": true, "clipboard.limit": 50, "clipboard.hotKey": hotKey,
            "fileDialog.favorites": ["/Users/me/Projects"], "AppleLanguages": ["ja"],
            "fileDialog.history": ["/private"], "onboardingCompleted": true,
        ]

        let data = try SettingsBackup.export(configurationFile: configurationFile, defaults: preferences, appVersion: "1.0 (1)")

        // Somewhere else, with other settings.
        try writeConfiguration(Configuration())
        let defaults = freshDefaults()
        defaults.set(10, forKey: "clipboard.limit")
        defaults.set(false, forKey: "menuBar.showsIcon")

        let contents = try SettingsBackup.read(data)
        #expect(contents.appVersion == "1.0 (1)")
        try SettingsBackup.apply(contents, configurationFile: configurationFile, defaults: defaults)

        #expect(try readConfiguration() == configuration)
        #expect(defaults.integer(forKey: "clipboard.limit") == 50)
        #expect(defaults.bool(forKey: "clipboard.enabled"))
        #expect(defaults.data(forKey: "clipboard.hotKey").flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
                == KeyCombo([.option], .v))
        #expect(defaults.stringArray(forKey: "fileDialog.favorites") == ["/Users/me/Projects"])
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["ja"])
        #expect(defaults.object(forKey: "menuBar.showsIcon") == nil, "Not in the backup: back to its default")
        #expect(defaults.object(forKey: "fileDialog.history") == nil, "Recent folders are not carried over")
        #expect(defaults.object(forKey: "onboardingCompleted") == nil, "Setup belongs to this Mac")
    }

    /// 1.0 and 1.1 backups carry the path box's settings, gone in SK-276.
    @Test func aBackupWithThePathBoxImportsWithoutIt() throws {
        let hotKey = try JSONSerialization.jsonObject(with: JSONEncoder().encode(KeyCombo([.command], .l)))
        let data = try JSONSerialization.data(withJSONObject: [
            "format": SettingsBackup.format, "version": 1, "app": "1.1 (2)",
            "configuration": JSONSerialization.jsonObject(with: JSONEncoder().encode(Configuration())),
            "preferences": ["pathBox.enabled": false, "pathBox.hotKey": hotKey, "clipboard.limit": 30],
        ])
        let contents = try SettingsBackup.read(data)
        #expect(contents.preferences.keys.sorted() == ["clipboard.limit"])
    }

    @Test func noConfigurationFileIsBackedUpAsTheDefaults() throws {
        let data = try SettingsBackup.export(configurationFile: configurationFile, defaults: [:], appVersion: "1.0 (1)")
        let contents = try SettingsBackup.read(data)
        let decoded = try JSONDecoder().decode(
            Configuration.self, from: JSONSerialization.data(withJSONObject: contents.configuration)
        )
        #expect(decoded == Configuration())
    }

    @Test func otherFilesAreRefused() {
        #expect(throws: SettingsBackup.BackupError.notABackup) {
            try SettingsBackup.read(Data("{\"schemaVersion\": 1}".utf8))
        }
        #expect(throws: SettingsBackup.BackupError.notABackup) {
            try SettingsBackup.read(Data("not json".utf8))
        }
    }

    @Test func aNewerFormatIsRefused() throws {
        func backup(version: Int, schema: Int) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "format": SettingsBackup.format, "version": version,
                "configuration": ["schemaVersion": schema], "preferences": [:],
            ])
        }
        #expect(throws: SettingsBackup.BackupError.newerFormat) {
            try SettingsBackup.read(backup(version: SettingsBackup.currentVersion + 1, schema: 1))
        }
        #expect(throws: SettingsBackup.BackupError.newerConfiguration) {
            try SettingsBackup.read(backup(version: 1, schema: Configuration.currentVersion + 1))
        }
    }

    @Test func theNewestBackupIsTheLatestByName() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(SettingsBackup.newestBackup(in: folder) == nil)
        for name in ["Before import 2026-10-05 221233.json", "Before import 2026-10-06 080000.json", "notes.txt"] {
            try Data().write(to: folder.appending(path: name))
        }
        #expect(SettingsBackup.newestBackup(in: folder)?.lastPathComponent == "Before import 2026-10-06 080000.json")
    }
}
