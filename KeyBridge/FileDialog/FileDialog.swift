import AppKit
import ApplicationServices
import OSLog

/// The open or save dialog in front, found and steered through Accessibility
/// (KB-217), which KeyBridge holds anyway.
///
/// Every app's dialog is AppKit's `NSOpenPanel` / `NSSavePanel`, drawn by a
/// system service for sandboxed apps and in the app itself otherwise, and in
/// both cases it appears in the app's own Accessibility tree with the same
/// identifiers: `open-panel` or `save-panel`, either as the window itself or
/// as a sheet on a document window. Nothing public says where a dialog is, so
/// going somewhere is done the way a person would: ⌘⇧G opens the dialog's own
/// Go to Folder sheet, the path goes into its field, and Return confirms —
/// setting the field and asking it to confirm through Accessibility alone
/// does not navigate. Measured on macOS 26.6; if a later macOS renames these
/// identifiers the shortcut stops matching and the key goes through as before.
@MainActor
enum FileDialog {
    /// Carries out a file dialog rule's action.
    static func perform(_ action: FileDialogAction) {
        switch action {
        case .finderFolder:
            guard let path = FinderFolder.frontWindowPath() ?? FinderRecentFolders.paths().first else {
                Logger.fileDialog.notice("No Finder folder to go to")
                NSSound.beep()
                return
            }
            jump(to: path)
        }
    }

    /// Whether an open or save dialog has the keyboard. Asked from the event
    /// tap, and only for rules that act on a dialog, so every query gives up
    /// after 50 ms.
    static func isFocused() -> Bool {
        panel(timeout: 0.05) != nil
    }

    /// Takes the dialog in front to `path`.
    static func jump(to path: String) {
        guard let panel = panel(timeout: timeout) else {
            Logger.fileDialog.notice("No open or save dialog in front")
            NSSound.beep()
            return
        }
        // A Go to Folder sheet already open is used as it is; ⌘⇧G again
        // would not open a second one.
        if goToField(in: panel) == nil { press(KeyCombo([.shift, .command], .g)) }
        fill(panel, with: path, attempts: 30)
    }

    // MARK: - Finding the dialog

    private static let timeout: Float = 0.1
    private static let panelIdentifiers: Set<String> = ["open-panel", "save-panel"]

    /// The dialog: the front app's focused window when it is one, the dialog
    /// sheet on it, or the dialog a sheet of its own belongs to — while Go to
    /// Folder is open, that sheet is what the app reports as focused. A
    /// sandboxed app's sheet leaves the app with no focused window at times,
    /// since the keyboard is in the system's dialog service, so the main
    /// window is asked too.
    private static func panel(timeout: Float) -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, timeout)
        var candidate = self.element(of: element, kAXFocusedWindowAttribute)
            ?? self.element(of: element, kAXMainWindowAttribute)
        // Window › dialog sheet › Go to Folder sheet is as deep as it goes.
        for _ in 0..<3 {
            guard let window = candidate else { return nil }
            AXUIElementSetMessagingTimeout(window, timeout)
            if isPanel(window) { return window }
            let sheet = children(of: window).first {
                string(of: $0, kAXRoleAttribute) == kAXSheetRole as String && isPanel($0)
            }
            if let sheet { return sheet }
            candidate = self.element(of: window, kAXParentAttribute)
        }
        return nil
    }

    private static func isPanel(_ element: AXUIElement) -> Bool {
        string(of: element, kAXIdentifierAttribute).map(panelIdentifiers.contains) ?? false
    }

    // MARK: - Going somewhere

    /// Waits for the Go to Folder sheet, then puts `path` in its field and
    /// confirms. The sheet takes a moment to appear after ⌘⇧G; checking every
    /// 30 ms for up to a second covers a slow app without holding up the
    /// main thread.
    private static func fill(_ panel: AXUIElement, with path: String, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            guard let field = goToField(in: panel) else {
                if attempts > 1 {
                    fill(panel, with: path, attempts: attempts - 1)
                } else {
                    Logger.fileDialog.error("Go to Folder did not open in the dialog")
                    NSSound.beep()
                }
                return
            }
            AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            let status = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, path as CFString)
            guard status == .success else {
                Logger.fileDialog.error("Could not fill Go to Folder: \(status.rawValue, privacy: .public)")
                return
            }
            // A moment for the field to take the text before Return reads it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                press(KeyCombo([], .returnKey))
                Logger.fileDialog.info("Jumped a dialog to \(path, privacy: .private)")
            }
        }
    }

    /// The path field of the dialog's Go to Folder sheet, once it is open.
    private static func goToField(in panel: AXUIElement) -> AXUIElement? {
        guard let sheet = children(of: panel).first(where: {
            string(of: $0, kAXIdentifierAttribute) == "GoToWindow"
        }) else { return nil }
        // The sheet is a handful of elements; the field is two levels down.
        var queue = [sheet]
        var visited = 0
        while !queue.isEmpty, visited < 80 {
            let element = queue.removeFirst()
            visited += 1
            if string(of: element, kAXIdentifierAttribute) == "PathTextField" { return element }
            queue += children(of: element)
        }
        return nil
    }

    private static func press(_ combo: KeyCombo) {
        for down in [true, false] {
            if let event = SyntheticEvent.key(combo, down: down) { SyntheticEvent.post(event) }
        }
    }

    // MARK: - Accessibility helpers

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (copy(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    private static func element(of element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    // MARK: - Self-test

    #if DEBUG
    /// KB_DEBUG_DIALOGJUMP: three seconds after launch, carries out
    /// `finderFolder` on the dialog in front as ⌃G would, and logs whether a
    /// dialog was found. Open a dialog in some app first and leave it in
    /// front; the shell cannot press the shortcut, KeyBridge can.
    static func selfTest() {
        guard ProcessInfo.processInfo.environment["KB_DEBUG_DIALOGJUMP"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
            Logger.fileDialog.notice(
                "dialogjump front=\(front, privacy: .public) dialog=\(isFocused(), privacy: .public) finder=\(FinderFolder.frontWindowPath() ?? "none", privacy: .public) recent=\(FinderRecentFolders.paths().first ?? "none", privacy: .public)"
            )
            perform(.finderFolder)
        }
    }
    #endif
}

extension Logger {
    static let fileDialog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge", category: "fileDialog")
}
