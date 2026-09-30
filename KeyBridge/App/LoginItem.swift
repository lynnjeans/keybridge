import Foundation
import Observation
import OSLog
import ServiceManagement

/// Whether KeyBridge opens when the user logs in (KB-242).
///
/// Nothing is stored. The state is the system's and is asked for each time,
/// so switching it off in System Settings shows here as well.
///
/// macOS keeps one login item per bundle identifier, not per copy (measured
/// on macOS 26.6, `docs/testing-notes.md` › Open at Login). One added by hand
/// under System Settings reads as enabled here and is removed by switching
/// off here. And the item moves to whichever copy last asked about it: only
/// reading the status from a second copy makes that copy the one opened at
/// login. So only the copy in the Applications folder asks. There, asking at
/// every launch also brings back an item that pointed at another copy.
@MainActor
@Observable
final class LoginItem {
    /// The system's side, replaceable in tests.
    struct System: Sendable {
        var isEnabled: @MainActor () -> Bool
        var register: @MainActor () throws -> Void
        var unregister: @MainActor () throws -> Void

        static let live = System(
            isEnabled: { SMAppService.mainApp.status == .enabled },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() }
        )
    }

    private(set) var isEnabled: Bool
    /// Set when the last change did not take, until one does.
    private(set) var hasFailed = false

    /// Whether this copy has anything to do with the login item: only the
    /// one in the Applications folder. Any other — on its disk image, in
    /// Downloads, in a build folder — never asks the system, reads as off
    /// and cannot be switched, because asking alone would make it the copy
    /// opened at login.
    let isAvailable: Bool

    @ObservationIgnored private let system: System

    init(isAvailable: Bool, system: System = .live) {
        self.isAvailable = isAvailable
        self.system = system
        isEnabled = isAvailable && system.isEnabled()
    }

    /// Whether the running copy is in the Applications folder.
    static var isInApplicationsFolder: Bool {
        InstallLocation.isInApplicationsFolder(path: Bundle.main.bundlePath, homeDirectory: NSHomeDirectory())
    }

    /// For the log and the diagnostic report, in English.
    var summary: String {
        isAvailable ? (isEnabled ? "on" : "off") : "not asked (this copy is outside Applications)"
    }

    /// Asks the system again. Called whenever the state is about to be shown.
    func refresh() {
        guard isAvailable else { return }
        let enabled = system.isEnabled()
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        // Changed in System Settings since: whatever failed here is settled.
        hasFailed = false
    }

    /// Adds or removes the login item. What `isEnabled` says afterwards is
    /// the system's answer, so a change that did not take reads as before.
    func set(_ enabled: Bool) {
        guard isAvailable else { return }
        refresh()
        guard enabled != isEnabled else {
            hasFailed = false
            return
        }
        do {
            if enabled { try system.register() } else { try system.unregister() }
        } catch {
            Logger.loginItem.error("Could not switch Open at Login \(enabled ? "on" : "off", privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        refresh()
        hasFailed = isEnabled != enabled
        if !hasFailed {
            Logger.loginItem.notice("Open at Login switched \(enabled ? "on" : "off", privacy: .public)")
        }
    }

    /// Opens System Settings › General › Login Items & Extensions.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

#if DEBUG
extension LoginItem.System {
    /// A stand-in that only remembers what it was told, so the switch can be
    /// looked at and clicked without touching this Mac's login items
    /// (`KB_DEBUG_LOGINITEM`).
    @MainActor
    static func inMemory(isEnabled: Bool) -> Self {
        @MainActor final class State { var isEnabled = false }
        let state = State()
        state.isEnabled = isEnabled
        return Self(
            isEnabled: { state.isEnabled },
            register: { state.isEnabled = true },
            unregister: { state.isEnabled = false }
        )
    }
}
#endif

extension Logger {
    static let loginItem = Logger(subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge", category: "loginItem")
}
