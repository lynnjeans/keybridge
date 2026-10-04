import AppKit
import FinderSync
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Saves a diagnostic report for the user to attach to a problem report.
struct DiagnosticsCard: View {
    let recorder: DiagnosticRecorder
    let makeReport: () async -> DiagnosticReport
    @State private var isExporting = false
    @State private var failure: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostics")
                            .font(.headline)
                        Text("A text file with SameKeys's version, permissions, settings and the log of the last three days, to attach to a problem report. Nothing you copied is included.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(isExporting ? "Exporting…" : "Export Diagnostics…", action: export)
                        .disabled(isExporting)
                }
                Divider()
                RecordingRow(recorder: recorder)
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
        panel.nameFieldStringValue = "SameKeys Diagnostics \(Date.now.formatted(.iso8601.year().month().day())).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        // Where a browser's file picker is likely to look when the report is
        // attached, rather than wherever the last save panel was.
        panel.directoryURL = URL.downloadsDirectory
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
        clipboard: ClipboardController,
        loginItem: LoginItem,
        keyboards: KeyboardList,
        pathBox: PathBoxController,
        locations: FileLocations,
        updates: UpdateController,
        recorder: DiagnosticRecorder,
        logArchive: LogArchive
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
            ("Keyboards", keyboards.connected.isEmpty ? "none found" : keyboards.connected.map(\.description).joined(separator: ", ")),
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
        loginItem.refresh()
        state.append(("Open at login", loginItem.summary))
        state.append(("Other remappers running", otherRemappers.running.isEmpty ? "none" : otherRemappers.running.joined(separator: ", ")))

        let groups = rules.preset.groups.map { "\($0.id) \(rules.isEnabled(group: $0.id) ? "on" : "off")" }
        let settings = Section(title: "Shortcuts", lines: [
            ("Preset", rules.preset.id),
            ("Groups", groups.joined(separator: ", ")),
            ("Ctrl shortcuts pressed with", rules.controlKey.rawValue),
            ("Win and Alt keys", rules.modifierLayout.rawValue),
            ("Set per keyboard (see Keyboards in effect)", rules.keyboardSettings.isEmpty ? "nothing" : rules.keyboardSettings.map {
                "\($0.keyboard.description): Ctrl shortcuts \($0.controlKey?.rawValue ?? "general"), Win and Alt \($0.modifierLayout?.rawValue ?? "general")"
            }.joined(separator: "; ")),
            ("Zoom modifiers", rules.zoomModifiers.names.joined(separator: "+")),
            ("Wheel direction", rules.wheelDirection.rawValue),
            ("Dock click minimizes", rules.dockClickMinimizes ? "on" : "off"),
            ("Ctrl+click selects", rules.ctrlClickSelects ? "on" : "off"),
            ("System shortcuts", SystemAction.allCases.map { function -> String in
                switch SymbolicHotKeys.current().shortcut(for: function) {
                case .combo(let combo): "\(function.rawValue) \(combo.caps(.mac).joined())"
                case .off: "\(function.rawValue) off"
                case .none: "\(function.rawValue) none"
                }
            }.joined(separator: ", ")),
            ("Active rules", "\(rules.activeRuleCount)"),
            ("Customized entries", "\(rules.customizedCount)"),
            ("Custom rules", "\(rules.customRules.count)"),
        ])

        // What each connected keyboard actually runs with (KB-247).
        let keyboardLines: [(label: String, value: String)] = keyboards.connected.isEmpty
            ? [("Keyboards", "none found")]
            : effectiveSettings(of: keyboards.connected, in: rules.configuration).enumerated().map {
                (label: "Keyboard \($0.offset + 1)", value: $0.element)
            }
        let keyboardSection = Section(title: "Keyboards in effect", lines: keyboardLines)

        let pathBoxState = (pathBox.isEnabled ? "on, " : "off, ") + pathBox.hotKey.caps(.mac).joined()
            + (pathBox.hotKeyProblem.map { " (\($0))" } ?? "")
        let lastCheck = updates.lastCheck.map { timestamp($0) } ?? "never"
        let updateState = "checks automatically \(updates.checksAutomatically ? "yes" : "no"), "
            + "downloads automatically \(updates.downloadsAutomatically ? "yes" : "no"), last check \(lastCheck)"
        let naturalScrolling = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        let other = Section(title: "Other settings", lines: [
            ("Path box (Finder)", pathBoxState),
            ("Recent folders listed", String(locations.recentLimit)),
            ("Finder extension", FIFinderSyncController.isExtensionEnabled ? "enabled" : "not enabled"),
            ("Updates", updateState),
            ("Natural scrolling (System Settings)", naturalScrolling ? "on" : "off"),
        ])

        // Settings only; the copies themselves stay on the Mac.
        let history = Section(title: "Clipboard history", lines: [
            ("Enabled", clipboard.isEnabled ? "yes" : "no"),
            ("Items kept", "\(clipboard.history.items.count) of \(clipboard.limit)"),
            ("Shortcut", clipboard.hotKey.caps(.mac).joined() + (clipboard.hotKeyProblem.map { " (\($0))" } ?? "")),
            ("Never recorded from", clipboard.excludedApps.joined(separator: ", ")),
        ])

        let configuration = try? String(contentsOf: ConfigurationStore.defaultFileURL, encoding: .utf8)
        let recording = recorder.startedAt.map {
            Recording(started: $0, isRunning: recorder.isRecording, lines: recorder.lines)
        }
        let (log, earlier) = await Task.detached(priority: .userInitiated) {
            (logSinceLaunch(), logArchive.earlierLaunches())
        }.value
        return DiagnosticReport(
            generated: generated,
            sections: [app, system, Section(title: "State", lines: state), settings, keyboardSection, other, history],
            configuration: configuration,
            recording: recording,
            log: log,
            earlierLaunches: earlier
        )
    }

    /// SameKeys's own log entries since it was launched. Earlier launches
    /// come from `LogArchive`: the log of other processes is not open to apps.
    nonisolated static func logSinceLaunch() -> [String] {
        LogArchive.entries().map(\.line)
    }
}

/// Starts and stops a diagnostic recording (KB-247), and says what it holds.
private struct RecordingRow: View {
    let recorder: DiagnosticRecorder

    var body: some View {
        AdaptiveRow {
            VStack(alignment: .leading, spacing: 2) {
                Text("Record Shortcuts")
                    .font(.headline)
                Text("When a shortcut does not do what you expect: start, press it again, then export. For five minutes SameKeys notes each shortcut, the keyboard it came from, the app in front and what it became. Letters typed on their own are never noted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                status
                    .font(.callout)
                    .monospacedDigit()
            }
            if recorder.isRecording {
                Button("Stop Recording") { recorder.stop() }
            } else {
                Button("Start Recording") { recorder.start() }
            }
        }
    }

    @ViewBuilder private var status: some View {
        if recorder.isRecording, let end = recorder.endsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label {
                    Text("Recording: \(recorder.lines.count) noted, \(Self.remaining(until: end, from: context.date)) left")
                } icon: {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                }
            }
        } else if recorder.startedAt != nil {
            Text("\(recorder.lines.count) shortcuts noted; they go into the next export.")
                .foregroundStyle(.secondary)
        }
    }

    private static func remaining(until end: Date, from now: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now).rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
