import Foundation
import OSLog

/// A copy of SameKeys's settings in one file, to restore on this Mac or
/// another (SK-270).
///
/// It holds the configuration file as it is on disk and SameKeys's own
/// preferences, listed in `preferenceKeys`. Left out on purpose: what was
/// copied and the recent folders, which are private and of no use elsewhere,
/// and setup progress, pause and Open at Login, which belong to this Mac.
///
/// JSON, so it can be read and mended by hand like the configuration file.
enum SettingsBackup {
    /// What the file says it is, so any other JSON is turned away.
    static let format = "SameKeys settings"

    /// The version of this file's layout. Raise it when the layout changes;
    /// a file with a higher one is refused, since this build cannot know
    /// what it holds.
    static let currentVersion = 1

    /// The preferences carried over. Shortcuts are stored as JSON data; they
    /// go into the file as JSON so it stays readable.
    static let preferenceKeys = [
        "clipboard.enabled", "clipboard.hotKey", "clipboard.limit", "clipboard.excludedApps",
        "pathBox.enabled", "pathBox.hotKey",
        "fileDialog.favorites", "fileDialog.recentLimit",
        "AppleLanguages", "SUEnableAutomaticChecks",
    ]
    static let dataKeys: Set<String> = ["clipboard.hotKey", "pathBox.hotKey"]

    enum BackupError: LocalizedError, Equatable {
        case notABackup
        case newerFormat
        case newerConfiguration

        var errorDescription: String? {
            switch self {
            case .notABackup:
                String(localized: "This file is not a SameKeys settings backup.")
            case .newerFormat, .newerConfiguration:
                String(localized: "This backup was made by a newer version of SameKeys. Update SameKeys, then import it again.")
            }
        }
    }

    /// What a backup file holds, checked.
    struct Contents {
        /// The configuration file's JSON object.
        var configuration: [String: Any]
        var preferences: [String: Any]
        /// The SameKeys version that wrote it, for the person to see.
        var appVersion: String?
    }

    // MARK: - Export

    /// The backup of the settings as they are now. A missing configuration
    /// file (nothing changed yet) is written as the defaults.
    static func export(
        configurationFile: URL, defaults: [String: Any], appVersion: String, date: Date = .now
    ) throws -> Data {
        var configuration: [String: Any]
        if let data = try? Data(contentsOf: configurationFile) {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BackupError.notABackup
            }
            configuration = object
        } else {
            configuration = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Configuration())) as! [String: Any]
        }
        var preferences: [String: Any] = [:]
        for key in preferenceKeys {
            guard let value = defaults[key] else { continue }
            if dataKeys.contains(key) {
                guard let data = value as? Data,
                      let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { continue }
                preferences[key] = object
            } else if JSONSerialization.isValidJSONObject([value]) {
                preferences[key] = value
            }
        }
        let backup: [String: Any] = [
            "format": format,
            "version": currentVersion,
            "app": appVersion,
            "exported": ISO8601DateFormatter().string(from: date),
            "configuration": configuration,
            "preferences": preferences,
        ]
        return try JSONSerialization.data(withJSONObject: backup, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: - Import

    /// Reads and checks a backup, changing nothing.
    static func read(_ data: Data) throws -> Contents {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["format"] as? String == format,
              let version = object["version"] as? Int,
              let configuration = object["configuration"] as? [String: Any],
              let schema = configuration["schemaVersion"] as? Int
        else { throw BackupError.notABackup }
        guard version <= currentVersion else { throw BackupError.newerFormat }
        guard schema <= Configuration.currentVersion else { throw BackupError.newerConfiguration }
        // An older configuration is upgraded by the store on the next launch,
        // as any old file is; the current one must decode now.
        if schema == Configuration.currentVersion {
            do {
                _ = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: configuration))
            } catch {
                throw BackupError.notABackup
            }
        }
        let preferences = (object["preferences"] as? [String: Any] ?? [:])
            .filter { preferenceKeys.contains($0.key) }
        return Contents(configuration: configuration, preferences: preferences, appVersion: object["app"] as? String)
    }

    /// Puts a backup's settings in place of the current ones: the
    /// configuration file, and every preference in `preferenceKeys`, so one
    /// the backup does not have goes back to its default. SameKeys restarts
    /// afterwards to take them all in.
    static func apply(_ contents: Contents, configurationFile: URL, defaults: UserDefaults) throws {
        try FileManager.default.createDirectory(
            at: configurationFile.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: contents.configuration, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: configurationFile, options: .atomic)
        for key in preferenceKeys {
            guard let value = contents.preferences[key] else {
                defaults.removeObject(forKey: key)
                continue
            }
            if dataKeys.contains(key) {
                guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else {
                    defaults.removeObject(forKey: key)
                    continue
                }
                defaults.set(data, forKey: key)
            } else {
                defaults.set(value, forKey: key)
            }
        }
        Logger.configuration.notice("Settings imported from a backup")
    }

    // MARK: - Where things go

    /// Backups SameKeys makes of the settings an import replaces.
    static var automaticBackupFolder: URL {
        URL.sameKeysSupport.appending(path: "Backups")
    }

    /// A file name with the date and time, the same shape for exports and the
    /// automatic backups, so they sort by when they were made.
    static func fileName(_ prefix: String, date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return "\(prefix) \(formatter.string(from: date)).json"
    }
}
