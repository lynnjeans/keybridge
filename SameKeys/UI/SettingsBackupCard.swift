import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Exports SameKeys's settings to a file and imports them back (SK-270).
struct SettingsBackupCard: View {
    @State private var failure: String?

    var body: some View {
        Card {
            AdaptiveRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings Backup")
                        .font(.headline)
                    Text("Save your shortcuts and settings to a file, to restore them later or on another Mac. What you copied is not included.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Import Settings…", action: importSettings)
                    Button("Export Settings…", action: exportSettings)
                }
            }
        }
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
            try Self.currentBackup().write(to: folder.appending(path: SettingsBackup.fileName("Before import")),
                                           options: .atomic)
            try SettingsBackup.apply(contents, configurationFile: Self.configurationFile, defaults: .standard)
        } catch {
            failure = error.localizedDescription
            return
        }
        Relaunch.now()
    }
}
