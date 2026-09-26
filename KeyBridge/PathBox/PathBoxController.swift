import AppKit
import Observation
import OSLog

/// The paste-a-path shortcut (KB-213): a hot key that, only while Finder is
/// frontmost, shows a small box to jump straight to a pasted path — the
/// closest KeyBridge gets to Windows' editable address bar without asking
/// for the Automation permission a real one would need.
@MainActor
@Observable
final class PathBoxController {
    /// On by default. A system hot key is swallowed in whatever app is in
    /// front, so this one is held only while Finder is there — ⌘L stays the
    /// address bar shortcut everywhere else — which leaves nothing for the
    /// switch to protect other apps from. It is here to turn the box itself
    /// off, as every other feature can be.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            update()
        }
    }

    /// The shortcut that shows the box.
    private(set) var hotKey: KeyCombo

    /// Why the shortcut does not work, when it does not.
    private(set) var hotKeyProblem: String?

    /// ⌘L, as browsers use to jump to their own address bar.
    static let defaultHotKey = KeyCombo([.command], .l)

    /// Shows the box; set by the app, which owns the panel.
    @ObservationIgnored var showPanel: (@MainActor () -> Void)?
    @ObservationIgnored private lazy var globalHotKey = GlobalHotKey { [weak self] in self?.handleHotKey() }
    @ObservationIgnored private let defaults: UserDefaults
    /// Whether Finder is the app in front; the app tells us, from the
    /// workspace notification it already watches for rule scoping.
    @ObservationIgnored private(set) var isFinderFront = false
    /// Set while the shortcut is let go of for recording, so an app switch
    /// cannot register it again behind the recorder's back.
    @ObservationIgnored private var isSuspended = false

    private enum Keys {
        static let enabled = "pathBox.enabled"
        static let hotKey = "pathBox.hotKey"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotKey = defaults.data(forKey: Keys.hotKey).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
            ?? Self.defaultHotKey
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        checkHotKey()
        update()
    }

    /// Which app is in front, as `FrontmostApplication` sees it. The hot key
    /// follows Finder in and out rather than being held for the session.
    func setFrontmostApplication(_ bundleID: String?) {
        let isFinder = bundleID == BuiltInRules.finderID
        guard isFinder != isFinderFront else { return }
        isFinderFront = isFinder
        update()
    }

    /// Changes the shortcut and registers it at once.
    func setHotKey(_ combo: KeyCombo) {
        hotKey = combo
        defaults.set(try? JSONEncoder().encode(combo), forKey: Keys.hotKey)
        checkHotKey()
        update()
    }

    /// Lets go of the shortcut while a new one is being recorded, so
    /// pressing the current one records it instead of showing the box.
    func suspendHotKey() {
        isSuspended = true
        globalHotKey.unregister()
    }

    func resumeHotKey() {
        isSuspended = false
        update()
    }

    /// Belt and braces: the shortcut is only held while Finder is in front,
    /// and the box has no other window to belong to.
    private func handleHotKey() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == BuiltInRules.finderID else { return }
        showPanel?()
    }

    /// Holds the shortcut only when it is on, Finder is in front, nothing is
    /// recording, and the system will have it.
    private func update() {
        guard isEnabled, isFinderFront, !isSuspended, hotKeyProblem == nil else {
            globalHotKey.unregister()
            return
        }
        try? globalHotKey.register(hotKey)
    }

    /// Tries the shortcut out to learn whether the system will take it, and
    /// says so. `update()` then decides whether to keep holding it. Asking
    /// now rather than at the next Finder activation is what lets the
    /// settings card show a problem at all: the settings window being in
    /// front means Finder is not.
    private func checkHotKey() {
        do {
            try globalHotKey.register(hotKey)
            hotKeyProblem = nil
        } catch .unsupportedModifier {
            hotKeyProblem = String(localized: "fn cannot be part of this shortcut. Choose one with ⌘, ⌥, ⌃ or ⇧.")
        } catch .taken {
            hotKeyProblem = String(localized: "Another app already uses this shortcut. Choose a different one.")
        } catch {
            hotKeyProblem = String(localized: "The shortcut could not be set up. Choose a different one.")
        }
        if let hotKeyProblem {
            Logger.pathBox.error("Hot key not registered: \(hotKeyProblem, privacy: .public)")
        }
    }
}

extension Logger {
    static let pathBox = Logger(subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge", category: "pathBox")
}
