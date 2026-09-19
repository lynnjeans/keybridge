import AppKit
import Carbon
import Observation
import OSLog

/// Watches macOS's Secure Input, which hides key presses from every event
/// tap — KeyBridge's included — while it is on. A password field turns it
/// on while it has focus; some apps turn it on for longer, such as Terminal
/// with Secure Keyboard Entry, or leave it on by mistake. Keyboard rules then
/// do nothing, which looks like a KeyBridge bug unless the user is told.
///
/// macOS sends no notification for it, so it is polled; the check is a
/// cheap system call.
@MainActor
@Observable
final class SecureInputMonitor {
    /// Who has Secure Input on right now, or nil while it is off.
    private(set) var holder: Holder?

    struct Holder: Equatable {
        /// The app that turned it on, when macOS says which.
        var appName: String?
        var bundleID: String?
        var since: Date
    }

    /// How long Secure Input has to stay on before it no longer looks like
    /// a password being typed, and the app holding it is worth naming.
    static let lingering: TimeInterval = 30

    /// Reads the current state: whether it is on, and the holder's process.
    struct Reading {
        var isOn: Bool
        var pid: pid_t?
    }

    @ObservationIgnored private let read: () -> Reading
    @ObservationIgnored private var timer: Timer?

    init(read: @escaping () -> Reading = SecureInputMonitor.systemReading) {
        self.read = read
    }

    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Whether Secure Input has been on long enough that someone is holding
    /// it rather than typing a password. Updated on each poll.
    private(set) var isLingering = false

    func refresh(now: Date = .now) {
        let reading = read()
        guard reading.isOn else {
            if holder != nil {
                Logger.permissions.notice("Secure Input off")
                holder = nil
                isLingering = false
            }
            return
        }
        let app = reading.pid.flatMap(NSRunningApplication.init(processIdentifier:))
        let bundleID = app?.bundleIdentifier
        // A new holder starts the clock again; the same one keeps it.
        if holder?.bundleID != bundleID || holder == nil {
            holder = Holder(appName: app?.localizedName, bundleID: bundleID, since: now)
            Logger.permissions.notice("Secure Input on, held by \(bundleID ?? "an unknown process", privacy: .public)")
        }
        let lingering = now.timeIntervalSince(holder!.since) >= Self.lingering
        if lingering != isLingering { isLingering = lingering }
    }

    nonisolated static func systemReading() -> Reading {
        let isOn = IsSecureEventInputEnabled()
        // The session dictionary names the process holding it.
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let pid = (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value
        return Reading(isOn: isOn, pid: pid)
    }
}

extension SecureInputMonitor.Holder {
    /// Where the user can switch it off, for apps known to offer that.
    var switchOffHint: String? {
        switch bundleID {
        case "com.apple.Terminal": String(localized: "In Terminal, uncheck Terminal › Secure Keyboard Entry.")
        case "com.googlecode.iterm2": String(localized: "In iTerm2, uncheck iTerm2 › Secure Keyboard Entry.")
        default: nil
        }
    }
}
