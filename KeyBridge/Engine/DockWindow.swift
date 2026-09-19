import AppKit
import ApplicationServices
import OSLog

/// The Accessibility side of `DockClick`: which window a click on the Dock
/// would minimize, and minimizing it. Uses the Accessibility permission
/// KeyBridge holds anyway.
@MainActor
enum DockWindow {
    /// The window to minimize when `point` is on the Dock icon of the
    /// frontmost app: its focused window, or else its main one, as long as it
    /// is a standard window that is showing and can be minimized. Nil for
    /// anything else, which leaves the click to the Dock alone. Each query
    /// gives up after 50 ms.
    static func target(forClickAt point: CGPoint) -> AXUIElement? {
        guard let front = NSWorkspace.shared.frontmostApplication, let frontURL = front.bundleURL,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }

        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let item = hit else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(item, &pid) == .success, pid == dock.processIdentifier,
              string(of: item, kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = copy(item, kAXURLAttribute) as? URL,
              url.path == frontURL.path
        else { return nil }

        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.05)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = element(of: app, attribute), canMinimize(window) { return window }
        }
        return nil
    }

    #if DEBUG
    /// KB_DEBUG_DOCKTEST: finds the frontmost app's Dock icon and runs the
    /// lookup a click there would, logging what it finds without minimizing
    /// anything. The click itself needs a person.
    static func selfTest() {
        guard ProcessInfo.processInfo.environment["KB_DEBUG_DOCKTEST"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let front = NSWorkspace.shared.frontmostApplication
            guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
            let app = AXUIElementCreateApplication(dock.processIdentifier)
            let lists = (copy(app, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            let items = lists.flatMap { (copy($0, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
            for item in items where string(of: item, kAXSubroleAttribute) == "AXApplicationDockItem" {
                guard let url = copy(item, kAXURLAttribute) as? URL, url.path == front?.bundleURL?.path,
                      let position = copy(item, kAXPositionAttribute), let size = copy(item, kAXSizeAttribute) else { continue }
                var origin = CGPoint.zero, extent = CGSize.zero
                AXValueGetValue(position as! AXValue, .cgPoint, &origin)
                AXValueGetValue(size as! AXValue, .cgSize, &extent)
                let center = CGPoint(x: origin.x + extent.width / 2, y: origin.y + extent.height / 2)
                let window = target(forClickAt: center)
                Logger.engine.notice("docktest front=\(front?.bundleIdentifier ?? "?", privacy: .public) icon=\(Int(center.x), privacy: .public),\(Int(center.y), privacy: .public) target=\(window == nil ? "none" : "window", privacy: .public)")
                // A point off the icon must find nothing.
                let off = target(forClickAt: CGPoint(x: center.x, y: origin.y - 200))
                Logger.engine.notice("docktest offIcon target=\(off == nil ? "none" : "window", privacy: .public)")
                return
            }
            Logger.engine.notice("docktest front=\(front?.bundleIdentifier ?? "?", privacy: .public) has no Dock icon; items=\(items.count, privacy: .public)")
        }
    }
    #endif

    static func minimize(_ window: AXUIElement) {
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        if result == .success {
            Logger.engine.notice("Dock click minimized the frontmost window")
        } else {
            Logger.engine.error("Dock click could not minimize the frontmost window: AXError \(result.rawValue, privacy: .public)")
        }
    }

    private static func canMinimize(_ window: AXUIElement) -> Bool {
        guard string(of: window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
              copy(window, kAXMinimizedAttribute) as? Bool == false else { return false }
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    private static func element(of element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
