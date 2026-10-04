import AppKit
import Observation
import OSLog

/// Keeps track of SameKeys's permissions while it runs and reports changes.
///
/// macOS sends no notification when the user grants or revokes Accessibility
/// or Input Monitoring, so the state is re-read whenever SameKeys becomes
/// active and on a light poll. Both checks are cheap system calls.
@MainActor
@Observable
final class PermissionMonitor {
    private(set) var statuses: [Permission: PermissionStatus]

    var allGranted: Bool {
        Permission.allCases.allSatisfy { status(of: $0) == .granted }
    }

    /// Called with the permissions whose status changed.
    @ObservationIgnored var onChange: (@MainActor (Set<Permission>) -> Void)?

    @ObservationIgnored private let service: PermissionService
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var hasRequestedInputMonitoring = false
    @ObservationIgnored private var pollsSinceFreshRead = 0

    /// With every permission granted, one poll in this many asks a fresh
    /// process: every 30 s at the usual 2 s poll.
    static let freshReadInterval = 15

    init(service: PermissionService = PermissionService()) {
        self.service = service
        statuses = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, service.status(of: $0)) })
    }

    func status(of permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .denied
    }

    /// Starts watching. Kept for the app's lifetime, so it is never undone.
    func start(pollInterval: TimeInterval = 2) {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    private func poll() {
        refresh()
        requestInputMonitoringIfUndecided()
    }

    /// Asks for Input Monitoring once per run, as soon as Accessibility is
    /// granted and Input Monitoring was never decided (KB-236).
    ///
    /// Only asking puts SameKeys in the Input Monitoring list, and with
    /// Accessibility granted macOS usually grants it silently. The guide used
    /// to be the only place that asked, so after its first run, or with
    /// the permissions reset, the list stayed empty and the user had to add
    /// SameKeys with + by hand.
    ///
    /// "Never decided" is read in this process: that is the permission
    /// record itself, which a fresh process does not report (it answers
    /// whether SameKeys may listen, which Accessibility can already allow).
    func requestInputMonitoringIfUndecided() {
        guard status(of: .accessibility) == .granted,
              !hasRequestedInputMonitoring,
              service.status(of: .inputMonitoring) == .notDetermined
        else { return }
        hasRequestedInputMonitoring = true
        service.request(.inputMonitoring)
        Logger.permissions.notice("Requested inputMonitoring: Accessibility is granted and it was never decided")
        refresh(fresh: true)
    }

    /// Re-reads every permission and reports the ones that changed.
    ///
    /// This process's own answers can be out of date (KB-236), so a process
    /// started for the purpose is asked instead: on every poll while a
    /// permission is missing, so a grant shows within seconds; every
    /// `freshReadInterval`-th poll otherwise, to notice a revocation; and
    /// whenever `fresh` is set.
    ///
    /// Between fresh reads nothing is read at all: this process's answers
    /// only stand in when a fresh read fails. Mixing the two made Input
    /// Monitoring flap between granted (fresh) and not determined (stale),
    /// stopping and restarting the tap.
    func refresh(fresh: Bool = false) {
        pollsSinceFreshRead += 1
        guard fresh || !allGranted || pollsSinceFreshRead >= Self.freshReadInterval else { return }
        pollsSinceFreshRead = 0
        let current = service.freshStatuses()
            ?? Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, service.status(of: $0)) })
        var changed: Set<Permission> = []
        for permission in Permission.allCases {
            let old = status(of: permission)
            let new = current[permission] ?? .denied
            guard new != old else { continue }
            statuses[permission] = new
            changed.insert(permission)
            Logger.permissions.notice(
                "\(permission.rawValue, privacy: .public): \(old.rawValue, privacy: .public) → \(new.rawValue, privacy: .public)"
            )
        }
        if !changed.isEmpty { onChange?(changed) }
    }
}
