import AppKit
import OSLog

/// Owns the app-lifetime services that SwiftUI scenes have no natural home for.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissionMonitor = PermissionMonitor()
    let secureInput = SecureInputMonitor()
    let otherRemappers = OtherRemapperMonitor()
    lazy var clipboard = ClipboardController()
    lazy var clipboardPanel = ClipboardPanelController(clipboard: clipboard)
    let frontmost = FrontmostApplication()
    let dockClick = DockClick(lookUp: DockWindow.target(forClickAt:), minimize: DockWindow.minimize)
    lazy var dispatcher = Dispatcher(
        frontmostBundleID: { [frontmost] in frontmost.bundleID },
        isEditingText: FocusedElement.isEditingText
    )
    /// The preset, the user's changes to it, and the rules that result. It
    /// hands each new set straight to the dispatcher, so a switch flipped in
    /// the window takes effect on the next key press.
    lazy var rules = RulesController(
        capture: { [dispatcher] recorder in dispatcher.recorder = recorder },
        applyWheelDirection: { [dispatcher] direction in dispatcher.wheelDirection = direction },
        applyDockClick: { [dockClick] minimizes in dockClick.isEnabled = minimizes },
        apply: { [dispatcher] rules in dispatcher.rules = rules }
    )
    lazy var eventTap = EventTap(dispatcher: dispatcher)
    lazy var engine = EngineController(permissions: permissionMonitor, tap: eventTap)
    lazy var onboarding = OnboardingController(permissions: permissionMonitor)

    func applicationDidFinishLaunching(_ notification: Notification) {
        logLaunchState()
        // Reading the configuration installs the first set of rules.
        _ = rules.effectiveRules
        permissionMonitor.start()
        secureInput.start()
        otherRemappers.start()
        clipboard.togglePanel = { [clipboardPanel] in clipboardPanel.toggle() }
        dispatcher.leftMouse = { [dockClick] event, type in
            let now = ProcessInfo.processInfo.systemUptime
            if type == .leftMouseDown {
                dockClick.mouseDown(at: event.location, flags: event.flags, time: now)
            } else {
                dockClick.mouseUp(at: event.location, time: now)
            }
        }
        engine.update()

        #if DEBUG
        if engine.isActive {
            EventTapSelfTest.runIfRequested(dispatcher: dispatcher)
        }
        LayoutCheck.showRequestedWindow(clipboardPanel: clipboardPanel)
        DockWindow.selfTest()
        // Writes the report the About page exports, without the save panel.
        if let path = ProcessInfo.processInfo.environment["KB_DEBUG_DIAGNOSTICS"] {
            Task { [self] in
                try? await Task.sleep(for: .seconds(3))
                let report = await DiagnosticReport.collect(engine: engine, rules: rules, secureInput: secureInput,
                                                            otherRemappers: otherRemappers, clipboard: clipboard)
                try? report.text.write(toFile: path, atomically: true, encoding: .utf8)
            }
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

    /// Records the version and permission state at launch, so a user's setup
    /// can be diagnosed from the system log.
    private func logLaunchState() {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        Logger.permissions.notice(
            "KeyBridge \(version, privacy: .public) on macOS \(DiagnosticReport.systemVersion, privacy: .public)"
        )
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
