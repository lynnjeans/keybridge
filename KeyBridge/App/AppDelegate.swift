import AppKit
import OSLog

/// Owns the app-lifetime services that SwiftUI scenes have no natural home for.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissions = PermissionService()
    let eventTap = EventTap()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logPermissionState()

        // The system refuses an active tap without Accessibility. Starting it
        // later, once the user grants permission, comes with live permission
        // refresh.
        if permissions.status(of: .accessibility) == .granted {
            eventTap.start()
            #if DEBUG
            EventTapSelfTest.runIfRequested()
            #endif
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
    }

    /// Records permission state at launch so a user's setup can be diagnosed
    /// from the system log.
    private func logPermissionState() {
        for permission in Permission.allCases {
            let status = permissions.status(of: permission)
            Logger.permissions.notice(
                "\(permission.rawValue, privacy: .public): \(status.rawValue, privacy: .public)"
            )
        }
    }
}
