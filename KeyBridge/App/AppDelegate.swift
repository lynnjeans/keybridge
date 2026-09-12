import AppKit
import OSLog

/// Owns the app-lifetime services that SwiftUI scenes have no natural home for.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissionMonitor = PermissionMonitor()
    let frontmost = FrontmostApplication()
    lazy var dispatcher: Dispatcher = {
        let dispatcher = Dispatcher { [frontmost] in frontmost.bundleID }
        dispatcher.rules = BuiltInRules.all
        return dispatcher
    }()
    lazy var eventTap = EventTap(dispatcher: dispatcher)

    func applicationDidFinishLaunching(_ notification: Notification) {
        logPermissionState()
        permissionMonitor.onChange = { [weak self] changed in self?.permissionsChanged(changed) }
        permissionMonitor.start()

        // The system refuses an active tap without Accessibility. If it is
        // missing now, the tap starts as soon as the monitor sees it granted.
        if permissionMonitor.status(of: .accessibility) == .granted {
            eventTap.start()
            #if DEBUG
            EventTapSelfTest.runIfRequested(dispatcher: dispatcher)
            #endif
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
    }

    /// Keeps the tap in line with the permissions, without a restart.
    private func permissionsChanged(_ changed: Set<Permission>) {
        let hasAccessibility = permissionMonitor.status(of: .accessibility) == .granted
        if !hasAccessibility {
            // Revoked while running. Stop cleanly, releasing any remapped key
            // still held, rather than leave a tap the system has cut off.
            eventTap.stop()
        } else if !eventTap.isRunning {
            eventTap.start()
        } else if changed.contains(.inputMonitoring) {
            // A tap created without Input Monitoring may go on being denied
            // key presses after the grant, so it is recreated.
            eventTap.stop()
            eventTap.start()
        }
    }

    /// Records permission state at launch so a user's setup can be diagnosed
    /// from the system log.
    private func logPermissionState() {
        for permission in Permission.allCases {
            let status = permissionMonitor.status(of: permission)
            Logger.permissions.notice(
                "\(permission.rawValue, privacy: .public): \(status.rawValue, privacy: .public)"
            )
        }
    }
}
