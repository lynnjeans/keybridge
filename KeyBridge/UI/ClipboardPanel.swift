import AppKit
import SwiftUI

/// The history panel, like Win+V on Windows: it comes up over whatever app
/// is in front, without taking the app's place — so the app stays the one
/// to paste into — and goes away as soon as the user clicks elsewhere.
@MainActor
final class ClipboardPanelController {
    private let clipboard: ClipboardController
    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?

    init(clipboard: ClipboardController) {
        self.clipboard = clipboard
    }

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: ClipboardPanelView(
            clipboard: clipboard,
            choose: { [weak self] item in self?.paste(item) },
            close: { [weak self] in self?.close() }
        ))
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// Puts the item on the pasteboard and pastes it into the app in front,
    /// as choosing an entry does on Windows. The item stays on the
    /// pasteboard, so any later paste gives it again.
    private func paste(_ item: ClipboardItem) {
        clipboard.restore(item)
        close()
        // Pasting is a ⌘V sent to the app; that needs Accessibility. Without
        // it the item is still on the pasteboard for the user to paste.
        guard CGPreflightPostEventAccess() else { return }
        // A moment for the app's window to take keyboard focus back from
        // the panel before the keystroke arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let paste = KeyCombo([.command], .v)
            for down in [true, false] {
                if let event = SyntheticEvent.key(paste, down: down) { SyntheticEvent.post(event) }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        // Clicking anywhere else dismisses it, as on Windows.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        return panel
    }

    /// Next to the pointer, kept inside the screen it is on.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - 20, y: mouse.y - size.height + 20)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }
}

/// A panel that takes keyboard input without activating KeyBridge.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Search on top, pinned items, then the rest; arrows move, Return chooses,
/// Esc closes.
private struct ClipboardPanelView: View {
    let clipboard: ClipboardController
    let choose: (ClipboardItem) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private var items: [ClipboardItem] {
        ClipboardSearch.ordered(ClipboardSearch.filter(clipboard.history.items, query))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard history…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 14)
            .padding(.top, 28)
            .padding(.bottom, 10)
            Divider()

            if items.isEmpty {
                Text(clipboard.history.items.isEmpty ? "Nothing copied yet" : "No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ClipboardRow(item: item, setPinned: { clipboard.history.setPinned(item.id, $0) })
                                    .padding(.horizontal, 8)
                                    .background(index == selection ? Color.accentColor.opacity(0.25) : .clear,
                                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .contentShape(.rect)
                                    .onTapGesture { choose(item) }
                                    .id(item.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selection) { _, index in
                        guard items.indices.contains(index) else { return }
                        proxy.scrollTo(items[index].id)
                    }
                }
            }
        }
        .frame(width: 380, height: 460)
        .onAppear { searchFocused = true }
        .onChange(of: query) { selection = 0 }
        .onKeyPress(.downArrow) {
            selection = min(selection + 1, max(items.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(selection - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            if items.indices.contains(selection) { choose(items[selection]) }
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }
}
