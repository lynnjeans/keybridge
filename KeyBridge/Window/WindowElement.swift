import AppKit
import ApplicationServices
import OSLog

/// Reading and writing the frontmost window's frame through the Accessibility
/// API (KB-200), the foundation the snap shortcuts are built on.
///
/// KeyBridge already holds the Accessibility permission for its event tap, so
/// nothing new is asked of the user. Every query gives up after 100 ms: an app
/// that is busy or wedged must not block the main queue, and a snap that does
/// not happen is better than a stalled keyboard. The budget is longer than the
/// 50 ms the event tap allows itself, because a window move is a deliberate
/// action a person is waiting for rather than a per-key check.
@MainActor
enum WindowElement {
    /// How long any one Accessibility call may take.
    static let timeout: Float = 0.1

    /// The window a snap should act on: the focused window of the frontmost
    /// app, or its main one, as long as it is an ordinary window that can be
    /// moved or resized.
    ///
    /// Nil for a full-screen window, a minimized one, and for panels, sheets
    /// and popovers, none of which a person means to snap.
    static func frontmost() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, timeout)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            guard let window = self.element(of: element, attribute) else { continue }
            AXUIElementSetMessagingTimeout(window, timeout)
            if isManageable(window) { return window }
        }
        return nil
    }

    /// The window's frame in Accessibility coordinates: the origin is the
    /// top-left of the primary display and y grows downwards.
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(of: window, kAXPositionAttribute),
              let size = size(of: window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Moves and resizes a window, and reports where it actually landed —
    /// which is not always what was asked. Apps enforce their own minimum and
    /// maximum sizes, and some refuse to resize at all; a terminal that snaps
    /// to whole character cells lands a few points short. The caller gets the
    /// truth rather than an assumption.
    ///
    /// The size is written, then the position, then the size again. An app
    /// that is still at its old size can clamp a move meant for a smaller
    /// frame, and one still at its old position can clamp a resize meant for
    /// another display; writing the size on both sides of the move is what
    /// makes a cross-display snap land in one step. The second write costs
    /// nothing when the first one took.
    @discardableResult
    static func setFrame(_ frame: CGRect, of window: AXUIElement) -> CGRect? {
        setSize(frame.size, of: window)
        setPosition(frame.origin, of: window)
        setSize(frame.size, of: window)
        return self.frame(of: window)
    }

    /// True when both halves of a frame can be written. A window that is only
    /// movable, like some utility panels, is left alone rather than half
    /// snapped.
    static func canSetFrame(_ window: AXUIElement) -> Bool {
        isSettable(window, kAXPositionAttribute) && isSettable(window, kAXSizeAttribute)
    }

    /// The displays, in Accessibility coordinates, ready for `WindowGeometry`.
    /// Empty only if `NSScreen` reports no screens at all.
    static func screens() -> [WindowGeometry.Screen] {
        guard let primary = NSScreen.screens.first else { return [] }
        let height = primary.frame.height
        return NSScreen.screens.map { screen in
            WindowGeometry.Screen(
                frame: WindowGeometry.flip(screen.frame, primaryHeight: height),
                visibleFrame: WindowGeometry.flip(screen.visibleFrame, primaryHeight: height)
            )
        }
    }

    // MARK: - Self-test

    #if DEBUG
    /// KB_DEBUG_WINDOWTEST: three seconds after launch, shrinks the frontmost
    /// window into the top-left quarter of its screen's usable area, logs what
    /// it asked for and what it got, then puts the window back where it was.
    /// Proof that a frame can be both read and written, without any UI to
    /// drive — the snap shortcuts arrive with KB-201.
    static func selfTest() {
        guard ProcessInfo.processInfo.environment["KB_DEBUG_WINDOWTEST"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            guard let window = frontmost() else {
                Logger.window.notice("windowtest front=\(app, privacy: .public) no manageable window")
                return
            }
            guard let original = frame(of: window) else {
                Logger.window.notice("windowtest front=\(app, privacy: .public) frame unreadable")
                return
            }
            guard canSetFrame(window) else {
                Logger.window.notice("windowtest front=\(app, privacy: .public) frame not settable")
                return
            }
            guard let screen = WindowGeometry.screen(for: original, among: screens()) else {
                Logger.window.notice("windowtest front=\(app, privacy: .public) no screen")
                return
            }
            let visible = screen.visibleFrame
            let wanted = WindowGeometry.fit(
                CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height / 2),
                in: visible
            )
            let landed = setFrame(wanted, of: window)
            Logger.window.notice(
                "windowtest front=\(app, privacy: .public) was=\(describe(original), privacy: .public) wanted=\(describe(wanted), privacy: .public) landed=\(landed.map(describe) ?? "unreadable", privacy: .public)"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                setFrame(original, of: window)
                Logger.window.notice("windowtest restored")
            }
        }
    }

    private static func describe(_ rect: CGRect) -> String {
        "\(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))"
    }
    #endif

    // MARK: - Accessibility plumbing

    /// An ordinary, on-screen window: standard subrole, not minimized and not
    /// in its own full-screen space, where a written frame is either ignored
    /// or throws the window out of the space.
    private static func isManageable(_ window: AXUIElement) -> Bool {
        guard string(of: window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
              copy(window, kAXMinimizedAttribute) as? Bool != true,
              copy(window, "AXFullScreen") as? Bool != true else { return false }
        return true
    }

    private static func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var value = point
        guard let wrapped = AXValueCreate(.cgPoint, &value) else { return }
        log(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, wrapped), "position")
    }

    private static func setSize(_ size: CGSize, of window: AXUIElement) {
        var value = size
        guard let wrapped = AXValueCreate(.cgSize, &value) else { return }
        log(AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, wrapped), "size")
    }

    private static func log(_ result: AXError, _ what: String) {
        guard result != .success else { return }
        Logger.window.error("Could not set window \(what, privacy: .public): AXError \(result.rawValue, privacy: .public)")
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private static func point(of element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(of: element, attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(of element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(of: element, attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func axValue(of element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
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

extension Logger {
    static let window = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge",
        category: "window"
    )
}
