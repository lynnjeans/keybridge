import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Saves a diagnostic report for the user to attach to a problem report.
struct DiagnosticsCard: View {
    let makeReport: () async -> DiagnosticReport
    @State private var isExporting = false
    @State private var failure: String?

    var body: some View {
        Card {
            AdaptiveRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnostics")
                        .font(.headline)
                    Text("A text file with KeyBridge's version, permissions, settings and log since launch, to attach to a problem report. Nothing you copied is included.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(isExporting ? "Exporting…" : "Export Diagnostics…", action: export)
                    .disabled(isExporting)
            }
        }
        .alert("The diagnostics could not be saved", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "KeyBridge Diagnostics \(Date.now.formatted(.iso8601.year().month().day())).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                try await makeReport().text.write(to: url, atomically: true, encoding: .utf8)
                Logger.permissions.notice("Diagnostics exported")
                // Shown in Finder, ready to drag into the report.
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

extension DiagnosticReport {
    /// The report as things stand now. The log takes a second or more to
    /// read, so that happens off the main thread.
    @MainActor
    static func collect(
        engine: EngineController,
        rules: RulesController,
        secureInput: SecureInputMonitor,
        otherRemappers: OtherRemapperMonitor,
        clipboard: ClipboardController
    ) async -> DiagnosticReport {
        let generated = Date.now
        let info = Bundle.main.infoDictionary
        let app = Section(title: "App", lines: [
            ("Version", "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"),
            ("Location", Bundle.main.bundlePath),
            ("Interface language", Bundle.main.preferredLocalizations.first ?? "?"),
        ])
        let system = Section(title: "System", lines: [
            ("macOS", systemVersion),
            ("Model", hardwareModel),
            ("Preferred languages", Locale.preferredLanguages.joined(separator: ", ")),
        ])

        var state: [(label: String, value: String)] = Permission.allCases.map {
            ("Permission \($0.rawValue)", engine.permissions.status(of: $0).rawValue)
        }
        state.append(("Windows Shortcut Mode", engine.isEnabled ? "on" : "off"))
        state.append(("Event tap running", engine.isActive ? "yes" : "no"))
        if let until = engine.pausedUntil {
            state.append(("Paused until", until == .distantFuture ? "resumed by hand" : timestamp(until)))
        }
        state.append(("Secure Input", secureInput.holder.map {
            "on, held by \($0.bundleID ?? $0.appName ?? "an unknown process")"
        } ?? "off"))
        state.append(("Other remappers running", otherRemappers.running.isEmpty ? "none" : otherRemappers.running.joined(separator: ", ")))

        let groups = rules.preset.groups.map { "\($0.id) \(rules.isEnabled(group: $0.id) ? "on" : "off")" }
        let settings = Section(title: "Shortcuts", lines: [
            ("Preset", rules.preset.id),
            ("Groups", groups.joined(separator: ", ")),
            ("Ctrl shortcuts pressed with", rules.controlKey.rawValue),
            ("Zoom modifiers", rules.zoomModifiers.names.joined(separator: "+")),
            ("Wheel direction", rules.wheelDirection.rawValue),
            ("Active rules", "\(rules.activeRuleCount)"),
            ("Customized entries", "\(rules.customizedCount)"),
            ("Custom rules", "\(rules.customRules.count)"),
        ])

        // Settings only; the copies themselves stay on the Mac.
        let history = Section(title: "Clipboard history", lines: [
            ("Enabled", clipboard.isEnabled ? "yes" : "no"),
            ("Items kept", "\(clipboard.history.items.count) of \(clipboard.limit)"),
            ("Shortcut", clipboard.hotKey.caps(.mac).joined() + (clipboard.hotKeyProblem.map { " (\($0))" } ?? "")),
            ("Never recorded from", clipboard.excludedApps.joined(separator: ", ")),
        ])

        let configuration = try? String(contentsOf: ConfigurationStore.defaultFileURL, encoding: .utf8)
        let log = await Task.detached(priority: .userInitiated) { logSinceLaunch() }.value
        return DiagnosticReport(
            generated: generated,
            sections: [app, system, Section(title: "State", lines: state), settings, history],
            configuration: configuration,
            log: log
        )
    }

    /// KeyBridge's own log entries since it was launched. Earlier launches
    /// are out of reach: the log of other processes is not open to apps.
    nonisolated static func logSinceLaunch(limit: Int = 5000) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let subsystem = Bundle.main.bundleIdentifier ?? "KeyBridge"
            let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
            let lines = entries.compactMap { entry -> String? in
                guard let log = entry as? OSLogEntryLog else { return nil }
                return "\(timestamp(log.date)) \(levelName(log.level)) [\(log.category)] \(log.composedMessage)"
            }
            return Array(lines.suffix(limit))
        } catch {
            return ["(the log could not be read: \(error.localizedDescription))"]
        }
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "-"
        }
    }
}
