import Foundation
import OSLog

/// Reads and writes the configuration file, upgrading files written by older
/// versions of KeyBridge on the way in.
///
/// The file is JSON, at `~/Library/Application Support/KeyBridge/config.json`,
/// so it can be read and, if need be, repaired by hand. Loading never fails:
/// whatever is wrong with the file, KeyBridge starts with the built-in rules
/// and keeps the file it could not use next to the new one.
struct ConfigurationStore: Sendable {
    /// Upgrades a file by one version: the step stored under `n` turns a
    /// version-`n` file into a version-`n + 1` one. Steps work on the raw JSON
    /// object, so they keep working however today's types change later.
    typealias Migration = @Sendable (inout [String: Any]) throws -> Void

    /// The upgrade steps this build knows. Empty while there has only been one
    /// version.
    static let migrations: [Int: Migration] = [:]

    static var defaultFileURL: URL {
        URL.keyBridgeSupport.appending(path: "config.json")
    }

    /// What `load()` found.
    enum Outcome: Equatable, Sendable {
        /// No file yet: a first run, or the user has changed nothing.
        case missing
        case loaded
        /// Upgraded from an older version; the original is kept as a backup.
        case migrated(from: Int)
        /// Not usable, so set aside at `backup`; the defaults are in effect.
        case unreadable(backup: URL)
        /// Written by a newer KeyBridge. Read as far as possible and never
        /// overwritten, so going back to that version loses nothing.
        case newer(version: Int)
    }

    enum StoreError: Error, Equatable {
        case notAConfiguration
        case noMigration(from: Int)
        /// Saving would replace a file written by a newer KeyBridge.
        case newerFileOnDisk(version: Int)
    }

    let fileURL: URL
    private let migrations: [Int: Migration]

    init(fileURL: URL = Self.defaultFileURL, migrations: [Int: Migration] = Self.migrations) {
        self.fileURL = fileURL
        self.migrations = migrations
    }

    func load() -> (configuration: Configuration, outcome: Outcome) {
        let result = read()
        switch result.outcome {
        case .missing:
            Logger.configuration.notice("No configuration file; using the built-in rules")
        case .loaded:
            Logger.configuration.notice("Configuration loaded: \(result.configuration.overrides.count, privacy: .public) override(s)")
        case .migrated(let version):
            Logger.configuration.notice("Configuration migrated from version \(version, privacy: .public) to \(Configuration.currentVersion, privacy: .public): \(result.configuration.overrides.count, privacy: .public) override(s)")
        case .unreadable(let backup):
            Logger.configuration.error("Configuration file unusable; set aside as \(backup.lastPathComponent, privacy: .public), using the built-in rules")
        case .newer(let version):
            Logger.configuration.error("Configuration file is version \(version, privacy: .public), newer than this build's \(Configuration.currentVersion, privacy: .public); reading it without saving")
        }
        return result
    }

    /// Writes the whole file at once, so a crash mid-write leaves the old one.
    func save(_ configuration: Configuration) throws {
        if let version = versionOnDisk(), version > Configuration.currentVersion {
            throw StoreError.newerFileOnDisk(version: version)
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(configuration).write(to: fileURL, options: .atomic)
    }

    private func read() -> (configuration: Configuration, outcome: Outcome) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return (Configuration(), .missing)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = object["schemaVersion"] as? Int
            else { throw StoreError.notAConfiguration }

            if version > Configuration.currentVersion {
                let configuration = (try? JSONDecoder().decode(Configuration.self, from: data)) ?? Configuration()
                return (configuration, .newer(version: version))
            }

            var upgraded = version
            while upgraded < Configuration.currentVersion {
                guard let step = migrations[upgraded] else { throw StoreError.noMigration(from: upgraded) }
                try step(&object)
                upgraded += 1
            }
            object["schemaVersion"] = upgraded
            let configuration = try JSONDecoder().decode(
                Configuration.self, from: JSONSerialization.data(withJSONObject: object)
            )
            guard version < Configuration.currentVersion else { return (configuration, .loaded) }

            // Keep the original, then write the upgraded file. If writing
            // fails the old file stays and is migrated again next launch.
            do {
                try FileManager.default.copyItem(at: fileURL, to: sibling("config.v\(version).json"))
                try save(configuration)
            } catch {
                Logger.configuration.error("Could not write the migrated configuration: \(error.localizedDescription, privacy: .public)")
            }
            return (configuration, .migrated(from: version))
        } catch {
            Logger.configuration.error("Configuration file unreadable: \(String(describing: error), privacy: .public)")
            return (Configuration(), .unreadable(backup: setAside()))
        }
    }

    /// Moves an unusable file out of the way, so the next save does not
    /// destroy something the user may want to recover.
    private func setAside() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = sibling("config.unreadable-\(formatter.string(from: Date())).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return backup
    }

    private func versionOnDisk() -> Int? {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["schemaVersion"] as? Int
    }

    private func sibling(_ name: String) -> URL {
        fileURL.deletingLastPathComponent().appending(path: name)
    }
}

extension Logger {
    static let configuration = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge",
        category: "configuration"
    )
}
