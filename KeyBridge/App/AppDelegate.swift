import AppKit
import OSLog

/// Owns the app-lifetime services that SwiftUI scenes have no natural home for.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissionMonitor = PermissionMonitor()
    let frontmost = FrontmostApplication()
    /// What the user has changed, read once at launch. Nothing edits it while
    /// the app runs yet, so a change to the file takes effect on relaunch.
    lazy var configuration = ConfigurationStore().load().configuration
    lazy var dispatcher: Dispatcher = {
        let dispatcher = Dispatcher { [frontmost] in frontmost.bundleID }
        dispatcher.rules = configuration.effectiveRules(base: BuiltInRules.all)
        return dispatcher
    }()
    lazy var eventTap = EventTap(dispatcher: dispatcher)
    lazy var engine = EngineController(permissions: permissionMonitor, tap: eventTap)
    lazy var onboarding = OnboardingController(permissions: permissionMonitor)

    func applicationDidFinishLaunching(_ notification: Notification) {
        logPermissionState()
        permissionMonitor.start()
        engine.update()

        #if DEBUG
        if engine.isActive {
            EventTapSelfTest.runIfRequested(dispatcher: dispatcher)
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
    }

    /// Opening KeyBridge again while it runs, from Finder or Spotlight, shows
    /// the main window. On a MacBook with a full menu bar the notch can hide
    /// the status item, and this is then the only way in.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        return false
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

extension Notification.Name {
    /// Asks the SwiftUI side to open the main window, which only a view can do.
    static let openMainWindow = Notification.Name("KeyBridgeOpenMainWindow")
}
