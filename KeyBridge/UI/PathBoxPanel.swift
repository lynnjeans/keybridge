import AppKit
import SwiftUI

/// The floating box the paste-a-path shortcut shows over Finder's window
/// (KB-213). Paste or type a path and press Return to jump to it; Escape or
/// clicking elsewhere dismisses it without navigating. It opens on the folder
/// Finder is showing, selected (KB-214), as Windows' address bar does when
/// clicked: what is typed or pasted replaces it, and it can be copied.
@MainActor
final class PathBoxPanelController {
    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?
    /// Told the folder the box went to, for the recent locations (KB-219).
    var visited: (@MainActor (String) -> Void)?

    /// `path` is where Finder already is; nil opens the box empty.
    func show(startingAt path: String? = nil) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: PathBoxView(
            path: path ?? "",
            navigate: { [weak self] text in
                // Return on the path it opened with goes nowhere new.
                if let path, PathBoxResolver.clean(text) == path {
                    self?.close()
                } else {
                    self?.navigate(text)
                }
            },
            close: { [weak self] in self?.close() }
        ))
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.focusFirstTextField()
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// A folder is opened; a file is revealed and selected in its parent, as
    /// Windows does when you paste a file's path into the address bar. An
    /// unresolved path beeps and leaves the box open to correct.
    private func navigate(_ text: String) {
        guard let target = PathBoxResolver.resolve(text) else {
            NSSound.beep()
            return
        }
        close()
        switch target {
        case let .folder(url):
            NSWorkspace.shared.open(url)
            visited?(url.path(percentEncoded: false).trimmingTrailingSlash)
        case let .file(url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
            visited?(url.deletingLastPathComponent().path(percentEncoded: false).trimmingTrailingSlash)
        }
    }

    private func makePanel() -> NSPanel {
        // The content rect is the box alone: `.titled` puts the title bar
        // (32pt on macOS 26) on top of it, and SwiftUI lays the box out below
        // that bar by itself. The bar names the box and the app that opened
        // it, for anyone who pressed ⌘L in Finder not knowing KeyBridge had
        // it, and is where the panel is dragged from.
        let panel = PathBoxKeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: PathBoxView.width, height: PathBoxView.height),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.title = "KeyBridge · " + String(localized: "Go to Path")
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        // Clicking anywhere else dismisses it, as the clipboard panel does.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        return panel
    }

    /// Just over the top of Finder's frontmost window; the pointer's screen,
    /// centred, when that window's frame cannot be read (a full-screen or
    /// minimized window, or one Accessibility does not expose).
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        if let window = WindowElement.frontmost(), let frame = WindowElement.frame(of: window),
           let primary = NSScreen.screens.first {
            let primaryHeight = primary.frame.height
            let cocoa = WindowGeometry.flip(frame, primaryHeight: primaryHeight)
            var origin = NSPoint(x: cocoa.midX - size.width / 2, y: cocoa.maxY - size.height - 40)
            // The screen the window mostly sits on, as macOS itself decides
            // it; those frames are in Accessibility coordinates, so the one
            // chosen is flipped back.
            if let screen = WindowGeometry.screen(for: frame, among: WindowElement.screens()) {
                let visible = WindowGeometry.flip(screen.visibleFrame, primaryHeight: primaryHeight)
                origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
                origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
            }
            panel.setFrameOrigin(origin)
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let visible = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame else {
            return
        }
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 80))
    }
}

/// A panel that takes keyboard input without activating KeyBridge, so Finder
/// stays the frontmost app while the box floats over it.
private final class PathBoxKeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct PathBoxView: View {
    static let width: CGFloat = 420
    static let height: CGFloat = 44

    let navigate: (String) -> Void
    let close: () -> Void
    @State private var text: String

    init(path: String, navigate: @escaping (String) -> Void, close: @escaping () -> Void) {
        _text = State(initialValue: path)
        self.navigate = navigate
        self.close = close
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            TextField("Paste or type a path…", text: $text)
                .textFieldStyle(.plain)
                .onSubmit { navigate(text) }
        }
        .padding(.horizontal, 14)
        .frame(width: Self.width, height: Self.height)
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }
}

private extension String {
    var trimmingTrailingSlash: String {
        count > 1 && hasSuffix("/") ? String(dropLast()) : self
    }
}
