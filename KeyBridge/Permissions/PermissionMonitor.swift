import AppKit
import Observation
import OSLog

/// Keeps track of KeyBridge's permissions while it runs and reports changes.
///
/// macOS sends no notification when the user grants or revokes Accessibility
/// or Input Monitoring, so the state is re-read whenever KeyBridge becomes
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
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Re-reads every permission and reports the ones that changed.
    func refresh() {
        var changed: Set<Permission> = []
        for permission in Permission.allCases {
            let old = status(of: permission)
            let new = service.status(of: permission)
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
