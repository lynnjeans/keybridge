import AppKit
import OSLog
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
        focusField(in: panel)
    }

    /// Puts the insertion point in the box, with the whole path selected so
    /// a paste replaces it instead of joining it. SwiftUI's `@FocusState`
    /// set from `onAppear` never reaches the field in this non-activating
    /// panel — the panel stays its own first responder — so AppKit is asked
    /// directly, once the hosting view has built the field, a run loop turn
    /// or two later. An `NSTextField` becoming first responder selects its
    /// text.
    private func focusField(in panel: NSPanel, attempts: Int = 10) {
        DispatchQueue.main.async { [weak self] in
            if let field = panel.contentView.flatMap(Self.textField(in:)) {
                panel.makeFirstResponder(field)
                // A long path shows its end, the folder the person is in,
                // rather than the start every path shares.
                if let editor = field.currentEditor() as? NSTextView {
                    editor.scrollRangeToVisible(NSRange(location: (editor.string as NSString).length, length: 0))
                }
            } else if attempts > 1 {
                self?.focusField(in: panel, attempts: attempts - 1)
            } else {
                Logger.pathBox.error("path box: no text field to focus")
            }
        }
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = textField(in: subview) { return field }
        }
        return nil
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
        case let .file(url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func makePanel() -> NSPanel {
        // The content rect is the box alone: `.titled` puts the title bar
        // (32pt on macOS 26) on top of it, and SwiftUI lays the box out below
        // that bar by itself. The bar carries the box's name, says what it
        // is for, and is where the panel is dragged from.
        let panel = PathBoxKeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: PathBoxView.width, height: PathBoxView.height),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.title = String(localized: "Go to Path")
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
