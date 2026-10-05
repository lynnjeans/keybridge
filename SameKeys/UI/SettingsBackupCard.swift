import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Exports SameKeys's settings to a file and imports them back (SK-270).
struct SettingsBackupCard: View {
    @State private var failure: String?
    /// The newest automatic backup, for Show Backups; looked up as the page
    /// appears.
    @State private var newestBackup: URL?

    var body: some View {
        Card {
            AdaptiveRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings Backup")
                        .font(.headline)
                    Text("Save your shortcuts and settings to a file, to restore them later or on another Mac. What you copied is not included. Before each import, your current settings are saved automatically: to undo an import, import that backup.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if let newestBackup {
                        Button("Show Backups") { NSWorkspace.shared.activateFileViewerSelecting([newestBackup]) }
                    }
                    Button("Import Settings…", action: importSettings)
                    Button("Export Settings…", action: exportSettings)
                }
            }
        }
        .onAppear { newestBackup = SettingsBackup.newestBackup() }
        .alert("Settings Backup", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(failure ?? "")
        }
    }

    private static var configurationFile: URL { ConfigurationStore.defaultFileURL }

    private static var currentPreferences: [String: Any] {
        UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func currentBackup() throws -> Data {
        try SettingsBackup.export(configurationFile: configurationFile, defaults: currentPreferences,
                                  appVersion: appVersion)
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SameKeys Settings \(Date.now.formatted(.iso8601.year().month().day())).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Self.currentBackup().write(to: url, options: .atomic)
            Logger.configuration.notice("Settings exported")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            failure = error.localizedDescription
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let contents: SettingsBackup.Contents
        do {
            contents = try SettingsBackup.read(Data(contentsOf: url))
        } catch {
            failure = error.localizedDescription
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Replace your settings with this backup?")
        alert.informativeText = String(localized: "All of SameKeys's settings are replaced by the ones in “\(url.lastPathComponent)”. Your current settings are saved first, in Application Support › SameKeys › Backups. SameKeys then restarts.")
        alert.addButton(withTitle: String(localized: "Import and Restart"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let folder = SettingsBackup.automaticBackupFolder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let backup = folder.appending(path: SettingsBackup.fileName("Before import"))
            try Self.currentBackup().write(to: backup, options: .atomic)
            try SettingsBackup.apply(contents, configurationFile: Self.configurationFile, defaults: .standard)
            UserDefaults.standard.set(backup.path, forKey: SettingsBackup.importNoticeKey)
        } catch {
            failure = error.localizedDescription
            return
        }
        Relaunch.now()
    }
}

/// After the restart an import causes, says where the settings it replaced
/// went and how to go back to them (SK-271). Once.
enum SettingsImportNotice {
    @MainActor
    static func showIfNeeded(defaults: UserDefaults = .standard) {
        guard let path = defaults.string(forKey: SettingsBackup.importNoticeKey) else { return }
        defaults.removeObject(forKey: SettingsBackup.importNoticeKey)
        let backup = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        // A moment for the menu bar item and the guide, if any, to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = String(localized: "Settings imported")
            alert.informativeText = String(localized: "Your previous settings were saved as “\(backup.lastPathComponent)”. To go back to them, import that file with Import Settings… on the About page.")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.addButton(withTitle: String(localized: "Show Backup"))
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([backup])
            }
        }
    }
}
