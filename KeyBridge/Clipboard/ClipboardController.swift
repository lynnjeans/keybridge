import AppKit
import Observation

/// The clipboard history as a feature: whether it is on, what it leaves out,
/// and the history itself. Its settings live in UserDefaults, apart from the
/// shortcut configuration, since they belong to a separate subsystem.
@MainActor
@Observable
final class ClipboardController {
    let history: ClipboardHistory

    /// Off until the user turns it on: it records what they copy.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            update()
        }
    }

    /// Apps whose copies are never recorded.
    private(set) var excludedApps: [String]

    @ObservationIgnored private let monitor: ClipboardMonitor
    @ObservationIgnored private let defaults: UserDefaults

    enum Keys {
        static let enabled = "clipboard.enabled"
        static let excludedApps = "clipboard.excludedApps"
        static let limit = "clipboard.limit"
    }

    init(pasteboard: NSPasteboard = .general, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let excluded = defaults.stringArray(forKey: Keys.excludedApps)
            ?? ClipboardPrivacy.defaultExcludedApps.sorted()
        let limit = defaults.object(forKey: Keys.limit) as? Int ?? 200
        let history = ClipboardHistory(limit: limit)
        self.history = history
        excludedApps = excluded
        isEnabled = defaults.bool(forKey: Keys.enabled)
        monitor = ClipboardMonitor(
            pasteboard: pasteboard, history: history,
            privacy: ClipboardPrivacy(excludedApps: Set(excluded))
        )
        update()
    }

    func exclude(_ bundleID: String) {
        guard !excludedApps.contains(bundleID) else { return }
        setExcludedApps(excludedApps + [bundleID])
    }

    func include(_ bundleID: String) {
        setExcludedApps(excludedApps.filter { $0 != bundleID })
    }

    func resetExcludedApps() {
        setExcludedApps(ClipboardPrivacy.defaultExcludedApps.sorted())
    }

    /// Checks the pasteboard now rather than at the next poll; for tests.
    func checkNow() {
        monitor.check()
    }

    private func setExcludedApps(_ apps: [String]) {
        excludedApps = apps
        defaults.set(apps, forKey: Keys.excludedApps)
        monitor.privacy = ClipboardPrivacy(excludedApps: Set(apps))
    }

    private func update() {
        if isEnabled && !monitor.isRunning {
            monitor.start()
        } else if !isEnabled && monitor.isRunning {
            monitor.stop()
        }
    }
}
