import AppKit
import Observation
import OSLog

/// The paste-a-path shortcut (KB-213): a global hot key that, only while
/// Finder is frontmost, shows a small box to jump straight to a pasted path
/// — the closest KeyBridge gets to Windows' editable address bar without
/// asking for the Automation permission a real one would need.
@MainActor
@Observable
final class PathBoxController {
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

    private enum Keys {
        static let hotKey = "pathBox.hotKey"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotKey = defaults.data(forKey: Keys.hotKey).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
            ?? Self.defaultHotKey
        registerHotKey()
    }

    /// Changes the shortcut and registers it at once.
    func setHotKey(_ combo: KeyCombo) {
        hotKey = combo
        defaults.set(try? JSONEncoder().encode(combo), forKey: Keys.hotKey)
        registerHotKey()
    }

    /// Lets go of the shortcut while a new one is being recorded, so
    /// pressing the current one records it instead of showing the box.
    func suspendHotKey() {
        globalHotKey.unregister()
    }

    func resumeHotKey() {
        registerHotKey()
    }

    /// Only while Finder is the frontmost app: there is no other window for
    /// the box to belong to, and no keybridge:// round trip is needed to
    /// find that out.
    private func handleHotKey() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == BuiltInRules.finderID else { return }
        showPanel?()
    }

    private func registerHotKey() {
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
