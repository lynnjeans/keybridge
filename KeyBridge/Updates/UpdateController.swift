import AppKit
import Observation
import OSLog
import Sparkle

/// Automatic updates through Sparkle (KB-101).
///
/// Sparkle checks once a day. A scheduled check never opens a window: an
/// update it finds puts a dot on the menu bar icon and an item at the top of
/// the menu, and Sparkle's window opens only when the user chooses that item.
/// A menu bar app has no Dock icon to badge, and an alert that pops up while
/// someone is typing is exactly what KeyBridge tries not to be. Only an
/// update the appcast marks critical is shown straight away.
@MainActor
@Observable
final class UpdateController: NSObject {
    /// An update found by a scheduled check that the user has not looked at
    /// yet, or one downloaded and waiting to be installed.
    struct Pending: Equatable {
        let version: String
        /// Downloaded by "Download and install automatically"; it installs
        /// on quit, or now through `installNow()`.
        var isDownloaded = false
    }

    private(set) var pending: Pending?
    /// False while a check or an update is in progress.
    private(set) var canCheckForUpdates = false
    private(set) var lastCheck: Date?
    let location = InstallLocation(bundleURL: Bundle.main.bundleURL)

    var checksAutomatically: Bool {
        didSet { updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    var downloadsAutomatically: Bool {
        didSet { updater.automaticallyDownloadsUpdates = downloadsAutomatically }
    }

    /// Whether the menu bar icon shows the dot.
    var needsAttention: Bool { pending != nil }

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var installHandler: (() -> Void)?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private var updater: SPUUpdater { controller.updater }

    override init() {
        checksAutomatically = false
        downloadsAutomatically = false
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    /// Starts the daily checks. Called once the app has finished launching.
    func start() {
        controller.startUpdater()
        readSettings()
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        Logger.updates.notice(
            "Updates: automatic checks \(self.checksAutomatically ? "on" : "off", privacy: .public), location \(String(describing: self.location), privacy: .public)"
        )
    }

    /// "Check for Updates…" in the menu and on the About page. Also brings
    /// back an update found earlier, which is what the menu's
    /// "Is Available…" item does.
    func checkForUpdates() {
        if let advice = location.advice {
            WindowID.activateKeyBridge()
            let alert = NSAlert()
            alert.messageText = String(localized: "Move KeyBridge to Applications")
            alert.informativeText = advice
            alert.runModal()
            return
        }
        // Sparkle's windows belong to KeyBridge, which as a menu bar app is
        // rarely the active app; without this the window opens in front but
        // the keyboard stays with the app the user was in.
        WindowID.activateKeyBridge()
        updater.checkForUpdates()
    }

    /// Takes the switches and the last check from Sparkle, which also changes
    /// them itself: its update window has its own "Automatically download
    /// and install" checkbox.
    private func readSettings() {
        if checksAutomatically != updater.automaticallyChecksForUpdates {
            checksAutomatically = updater.automaticallyChecksForUpdates
        }
        if downloadsAutomatically != updater.automaticallyDownloadsUpdates {
            downloadsAutomatically = updater.automaticallyDownloadsUpdates
        }
        lastCheck = updater.lastUpdateCheckDate
    }

    /// Installs a downloaded update and relaunches ("Restart to Update").
    /// Without a handler from Sparkle, its own window offers the same.
    func installNow() {
        if let installHandler {
            installHandler()
        } else {
            checkForUpdates()
        }
    }
}

// MARK: - Sparkle

extension UpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        // Scheduled checks from a place Sparkle cannot update would only find
        // updates that fail to install; `checkForUpdates()` explains instead.
        if location != .updatable {
            throw NSError(domain: "KeyBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: location.advice ?? ""])
        }
        #if DEBUG
        // Development builds carry build number 1 and would replace
        // themselves with the latest release.
        if Self.debugFeed == nil {
            throw NSError(domain: "KeyBridge", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Development builds do not update themselves. Set KB_DEBUG_APPCAST to a test appcast to try updates.",
            ])
        }
        #endif
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        return Self.debugFeed
        #else
        return nil
        #endif
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        readSettings()
        if let error {
            Logger.updates.notice("Update check ended: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// With "Download and install automatically" on, a downloaded update
    /// waits for the next quit. KeyBridge seldom quits, so the menu offers
    /// to install it now.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        Logger.updates.notice("Update \(item.displayVersionString, privacy: .public) downloaded; installs on quit")
        installHandler = immediateInstallHandler
        pending = Pending(version: item.displayVersionString, isDownloaded: true)
        return true
    }
}

extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Critical updates are shown at once; others wait behind the dot.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        update.isCriticalUpdate
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            // Sparkle's window is about to open; bring it in front.
            WindowID.activateKeyBridge()
        } else {
            Logger.updates.notice("Update \(update.displayVersionString, privacy: .public) available")
            pending = Pending(version: update.displayVersionString, isDownloaded: state.stage != .notDownloaded)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        // A downloaded update keeps its "Restart to Update" item until it
        // is installed.
        if pending?.isDownloaded != true { pending = nil }
    }

    func standardUserDriverWillFinishUpdateSession() {
        readSettings()
        if pending?.isDownloaded != true { pending = nil }
    }
}

#if DEBUG
extension UpdateController {
    /// A test appcast for development builds, e.g. one served from
    /// `python3 -m http.server`.
    nonisolated static var debugFeed: String? {
        ProcessInfo.processInfo.environment["KB_DEBUG_APPCAST"]
    }
}
#endif

extension Logger {
    static let updates = Logger(subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge", category: "updates")
}
