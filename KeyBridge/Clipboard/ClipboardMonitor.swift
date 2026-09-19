import AppKit
import OSLog

/// Notices every copy and hands what may be kept to the history.
///
/// macOS has no notification for pasteboard changes; its change count is
/// polled instead, twice a second. Reading the count is a cheap call, and
/// the contents are only read when it has moved.
@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let history: ClipboardHistory
    var privacy: ClipboardPrivacy
    /// The app in front when the copy happened, for copies that do not say
    /// where they came from.
    private let frontmostBundleID: @MainActor () -> String?

    private var lastChangeCount: Int
    private var timer: Timer?

    /// Copies larger than this are not kept: a huge image would bloat the
    /// history file for little use.
    static let maximumSize = 10 * 1024 * 1024

    init(
        pasteboard: NSPasteboard = .general,
        history: ClipboardHistory,
        privacy: ClipboardPrivacy,
        frontmostBundleID: @escaping @MainActor () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) {
        self.pasteboard = pasteboard
        self.history = history
        self.privacy = privacy
        self.frontmostBundleID = frontmostBundleID
        lastChangeCount = pasteboard.changeCount
    }

    var isRunning: Bool { timer != nil }

    /// Starts watching. What was on the pasteboard before is not recorded:
    /// only copies made while the history is on.
    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Logger.clipboard.notice("Clipboard history on")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        Logger.clipboard.notice("Clipboard history off")
    }

    /// Records the pasteboard if it changed since the last look.
    func check() {
        guard isRunning else { return }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        capture()
    }

    private func capture() {
        guard let pasteboardItem = pasteboard.pasteboardItems?.first else { return }
        let types = pasteboardItem.types.map(\.rawValue)
        // Apps following nspasteboard.org name themselves; others are taken
        // to be the app in front.
        let source = pasteboard.string(forType: .init("org.nspasteboard.source")) ?? frontmostBundleID()

        let verdict = privacy.verdict(types: types, sourceBundleID: source)
        guard verdict == .keep else {
            // What was skipped is never logged, only that something was.
            Logger.clipboard.info("Copy skipped: \(String(describing: verdict), privacy: .public)")
            return
        }

        var contents: [String: Data] = [:]
        var size = 0
        for type in ClipboardItem.keptTypes {
            guard let data = pasteboardItem.data(forType: type) else { continue }
            size += data.count
            contents[type.rawValue] = data
        }
        guard !contents.isEmpty else { return }
        guard size <= Self.maximumSize else {
            Logger.clipboard.info("Copy skipped: \(size, privacy: .public) bytes is over the limit")
            return
        }
        history.add(ClipboardItem(date: .now, sourceBundleID: source, contents: contents))
    }
}

extension Logger {
    static let clipboard = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge",
        category: "clipboard"
    )
}
