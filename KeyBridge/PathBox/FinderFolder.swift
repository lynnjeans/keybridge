import AppKit
import ApplicationServices
import OSLog

/// Where Finder is (KB-214): the folder its frontmost window is showing, so
/// the path box can open on it the way clicking Windows' address bar shows
/// where you are.
///
/// Read through Accessibility, which KeyBridge already holds; asking Finder
/// over AppleScript would be exact but needs the Automation permission, a
/// second prompt the path box was built to avoid. Finder leaves the window's
/// `AXDocument` empty, so the answer is pieced together from the window's
/// title, its path bar and the items in view — `FinderFolderPicker` explains
/// the rules. Depends on the shape of Finder's window as of macOS 26; if a
/// later Finder changes it, the box opens empty, which is what it did before.
@MainActor
enum FinderFolder {
    /// What was read from one window, and what it came to.
    struct Reading {
        var title = ""
        var crumbs: [FinderFolderPicker.Crumb] = []
        var itemPaths: [String] = []
        var path: String?
        var elements = 0
    }

    /// The path the box opens on. Nil when Finder is not the app in front,
    /// when the desktop rather than a window has the focus, and when the
    /// window has no single folder behind it — Recents, a search, AirDrop.
    static func currentPath() -> String? {
        guard let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == BuiltInRules.finderID else { return nil }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let window = element(of: app, kAXFocusedWindowAttribute) else { return nil }
        let start = Date()
        let reading = read(window)
        Logger.pathBox.info(
            "finderfolder path=\(reading?.path ?? "none", privacy: .private) elements=\(reading?.elements ?? 0, privacy: .public) ms=\(Int(Date().timeIntervalSince(start) * 1000), privacy: .public)"
        )
        return reading?.path
    }

    /// The folder of Finder's front window, whether or not Finder is the app
    /// in front: what an open or save dialog in another app jumps to
    /// (KB-217). Finder's focused window is its front one even while another
    /// app is active; failing that (the desktop has the focus), its main
    /// window, then the first ordinary window it lists. Only that one window
    /// counts: when it shows no folder (Recents, a search) the answer is nil
    /// rather than some window further back.
    static func frontWindowPath() -> String? {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: BuiltInRules.finderID).first else {
            return nil
        }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, timeout)
        var windows = [kAXFocusedWindowAttribute, kAXMainWindowAttribute].compactMap { element(of: app, $0) }
        windows += (copy(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.lazy.compactMap(read).first?.path
    }

    /// Nil for anything but an ordinary Finder window: the desktop is a
    /// window of Finder's too, with no subrole.
    static func read(_ window: AXUIElement) -> Reading? {
        AXUIElementSetMessagingTimeout(window, timeout)
        guard string(of: window, kAXSubroleAttribute) == kAXStandardWindowSubrole as String else { return nil }
        var reading = Reading()
        reading.title = string(of: window, kAXTitleAttribute) ?? ""
        var content: AXUIElement?
        walk(window, depth: 0, into: &reading, content: &content)
        reading.path = pick(reading)
        // The items are only needed without the path bar, and cost the most
        // to read.
        if reading.path == nil, let content {
            collectItems(content, depth: 0, into: &reading)
            reading.path = pick(reading)
        }
        return reading
    }

    private static func pick(_ reading: Reading) -> String? {
        let fileManager = FileManager.default
        return FinderFolderPicker.folder(
            title: reading.title,
            crumbs: reading.crumbs,
            itemPaths: reading.itemPaths,
            names: { [fileManager.displayName(atPath: $0), ($0 as NSString).lastPathComponent] },
            isFolder: { path in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
        )
    }

    // MARK: - Walking the window

    /// How long any one Accessibility call may take, as for window snapping.
    private static let timeout: Float = 0.1
    /// Finder's views of a folder's contents, by `AXIdentifier`.
    private static let contentViews: Set<String> = ["ListView", "IconView", "GalleryView", "ColumnView"]
    /// Items read per list: enough to see which folder they are in. A large
    /// folder must not cost more than a small one — reading every item of a
    /// 57-item Trash took 290 ms.
    private static let itemsPerList = 3
    /// Columns read in column view.
    private static let columns = 3
    /// A ceiling on the whole walk, should Finder's window ever grow a shape
    /// this does not expect.
    private static let maxElements = 400
    /// Parts of the window with neither the path bar nor items in them.
    private static let skippedRoles: Set<String> = [
        kAXToolbarRole as String, kAXTabGroupRole as String, kAXScrollBarRole as String, kAXButtonRole as String,
    ]

    /// Collects the path bar and finds the view of the folder's contents,
    /// descending only where they are: not into the sidebar (an outline that
    /// is not the list view), the toolbar, the tab bar or scroll bars.
    private static func walk(
        _ element: AXUIElement, depth: Int, into reading: inout Reading, content: inout AXUIElement?
    ) {
        guard depth < 10, reading.elements < maxElements else { return }
        reading.elements += 1
        let role = string(of: element, kAXRoleAttribute) ?? ""
        let identifier = string(of: element, kAXIdentifierAttribute)
        if role == kAXOutlineRole as String, identifier != "ListView" { return }
        if skippedRoles.contains(role) { return }
        if let identifier, contentViews.contains(identifier) {
            content = element
            return
        }
        let children = self.children(of: element)
        if role == kAXListRole as String, let crumbs = crumbs(in: children) {
            reading.crumbs = crumbs
            return
        }
        for child in children { walk(child, depth: depth + 1, into: &reading, content: &content) }
    }

    /// The path bar is a list of static texts, each carrying the URL of the
    /// folder it names. Nil for any other list.
    private static func crumbs(in children: [AXUIElement]) -> [FinderFolderPicker.Crumb]? {
        guard let first = children.first,
              string(of: first, kAXRoleAttribute) == kAXStaticTextRole as String,
              copy(first, kAXURLAttribute) != nil else { return nil }
        return children.map { child in
            FinderFolderPicker.Crumb(
                name: string(of: child, kAXValueAttribute) ?? "",
                path: filePath(copy(child, kAXURLAttribute))
            )
        }
    }

    /// Paths of the first few items of every list or outline in a content
    /// view. In column view, of the last few columns only: the folder the
    /// window is named after is the last column, or the one before it when a
    /// folder is selected, and the columns further left can run back to
    /// the disk.
    private static func collectItems(_ element: AXUIElement, depth: Int, into reading: inout Reading) {
        guard depth < 12, reading.elements < maxElements else { return }
        reading.elements += 1
        if let path = filePath(copy(element, kAXURLAttribute)) {
            reading.itemPaths.append(path)
            return
        }
        let role = string(of: element, kAXRoleAttribute) ?? ""
        var children = self.children(of: element)
        switch role {
        case kAXBrowserRole as String:
            children = Array(((copy(element, kAXColumnsAttribute) as? [AXUIElement]) ?? []).suffix(columns))
            for column in children { AXUIElementSetMessagingTimeout(column, timeout) }
        case kAXOutlineRole as String:
            // An outline lists its columns among its children; only rows
            // hold items.
            children = Array(children.filter { string(of: $0, kAXRoleAttribute) == kAXRowRole as String }
                .prefix(itemsPerList))
        case kAXListRole as String:
            children = Array(children.prefix(itemsPerList))
        case kAXScrollBarRole as String:
            return
        default:
            break
        }
        for child in children {
            let before = reading.itemPaths.count
            collectItems(child, depth: depth + 1, into: &reading)
            // An item's icon and name carry the same URL; one is enough.
            if reading.itemPaths.count > before, role == kAXGroupRole as String { break }
        }
    }

    // MARK: - Accessibility helpers

    /// Finder's items and path bar carry file-reference URLs
    /// (`file:///.file/id=…`); only a real path helps the box. Nil for
    /// anything else, such as Network's `nwnode:` URLs.
    private static func filePath(_ value: CFTypeRef?) -> String? {
        guard let value, CFGetTypeID(value) == CFURLGetTypeID() else { return nil }
        guard let path = (value as! NSURL).filePathURL?.path(percentEncoded: false) else { return nil }
        // A folder's URL ends in a slash; the box shows a path the way Copy
        // Path and a shell write one.
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Each child gets the timeout as well: an element without one of its
    /// own waits about 1.5 s on a Finder that does not answer.
    private static func children(of element: AXUIElement) -> [AXUIElement] {
        let children = (copy(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        for child in children { AXUIElementSetMessagingTimeout(child, timeout) }
        return children
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
        let result = value as! AXUIElement
        AXUIElementSetMessagingTimeout(result, timeout)
        return result
    }

    // MARK: - Self-test

    #if DEBUG
    /// KB_DEBUG_FINDERPATH: two seconds after launch, logs what each of
    /// Finder's windows comes to (KB-214): its title, the path bar's last
    /// segment, how many items were read and the folder chosen. Finder need
    /// not be in front and nothing is changed.
    static func selfTest() {
        guard ProcessInfo.processInfo.environment["KB_DEBUG_FINDERPATH"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let finder = NSRunningApplication
                .runningApplications(withBundleIdentifier: BuiltInRules.finderID).first else {
                Logger.pathBox.notice("finderpath Finder is not running")
                return
            }
            let app = AXUIElementCreateApplication(finder.processIdentifier)
            AXUIElementSetMessagingTimeout(app, timeout)
            let windows = (copy(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
            for window in windows {
                let start = Date()
                guard let reading = read(window) else { continue }
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                Logger.pathBox.notice(
                    "finderpath title=\(reading.title, privacy: .public) lastCrumb=\(reading.crumbs.last?.path ?? "none", privacy: .public) crumbs=\(reading.crumbs.count, privacy: .public) items=\(reading.itemPaths.count, privacy: .public) path=\(reading.path ?? "none", privacy: .public) elements=\(reading.elements, privacy: .public) ms=\(ms, privacy: .public)"
                )
            }
        }
    }
    #endif
}
