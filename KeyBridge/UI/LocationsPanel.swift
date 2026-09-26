import AppKit
import SwiftUI

/// The recent locations list (KB-219): favorite, open and recent folders over
/// the dialog or Finder window in front, without taking the app's place, so
/// the dialog is still the one to jump. Goes away on a click elsewhere.
@MainActor
final class LocationsPanelController {
    private let locations: FileLocations
    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?

    init(locations: FileLocations) {
        self.locations = locations
    }

    /// `choose` is told the folder picked; the panel is closed by then.
    func show(_ entries: [FileLocations.Location], choose: @escaping @MainActor (String) -> Void) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: LocationsPanelView(
            entries: entries,
            locations: locations,
            choose: { [weak self] path in
                self?.close()
                choose(path)
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

    private func makePanel() -> NSPanel {
        // As the clipboard panel: the title bar says which app opened it.
        let panel = LocationsKeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: LocationsPanelView.width, height: LocationsPanelView.height),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.title = "KeyBridge · " + String(localized: "Recent Locations")
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        return panel
    }

    /// Centred near the top of the front app's window — the dialog, or the
    /// document window its dialog sheet hangs from, or Finder's window —
    /// kept inside that window's screen; centred on the pointer's screen
    /// when the window cannot be read.
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        guard let primary = NSScreen.screens.first else { return }
        if let frame = Self.frontWindowFrame() {
            let cocoa = WindowGeometry.flip(frame, primaryHeight: primary.frame.height)
            var origin = NSPoint(x: cocoa.midX - size.width / 2, y: cocoa.maxY - size.height - 60)
            if let screen = WindowGeometry.screen(for: frame, among: WindowElement.screens()) {
                let visible = WindowGeometry.flip(screen.visibleFrame, primaryHeight: primary.frame.height)
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

    /// The front app's focused window, in Accessibility coordinates.
    private static func frontWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.1)
        var position = CGPoint.zero
        var size = CGSize.zero
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}

/// A panel that takes keyboard input without activating KeyBridge.
private final class LocationsKeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Search on top, then favorites, Finder's open folders and recent ones;
/// arrows move, Return chooses, ⌘D adds or removes a favorite, Esc closes.
private struct LocationsPanelView: View {
    static let width: CGFloat = 440
    static let height: CGFloat = 400

    let entries: [FileLocations.Location]
    let locations: FileLocations
    let choose: (String) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var selection = 0

    private var shown: [FileLocations.Location] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search folders…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 10)
            Divider()

            if shown.isEmpty {
                Text(entries.isEmpty ? "No folders yet. Folders you open in Finder show up here." : "No matches")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, location in
                                if index == 0 || shown[index - 1].kind != location.kind {
                                    Text(Self.heading(location.kind))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.top, index == 0 ? 2 : 8)
                                }
                                LocationRow(path: location.path, isFavorite: locations.isFavorite(location.path)) {
                                    locations.setFavorite(location.path, $0)
                                }
                                .padding(.horizontal, 8)
                                .background(index == selection ? Color.accentColor.opacity(0.25) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .contentShape(.rect)
                                .onTapGesture { choose(location.path) }
                                .id(location.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selection) { _, index in
                        guard shown.indices.contains(index) else { return }
                        proxy.scrollTo(shown[index].id)
                    }
                }
            }
        }
        .frame(width: Self.width, height: Self.height)
        .onChange(of: query) { selection = 0 }
        .onKeyPress(.downArrow) {
            selection = min(selection + 1, max(shown.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(selection - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            if shown.indices.contains(selection) { choose(shown[selection].path) }
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onKeyPress(characters: ["d"], phases: .down) { press in
            guard press.modifiers == .command, shown.indices.contains(selection) else { return .ignored }
            let path = shown[selection].path
            locations.setFavorite(path, !locations.isFavorite(path))
            return .handled
        }
    }

    private static func heading(_ kind: FileLocations.Location.Kind) -> String {
        switch kind {
        case .favorite: String(localized: "Favorites")
        case .finderWindow: String(localized: "Open in Finder")
        case .recent: String(localized: "Recent")
        }
    }
}

/// A folder: its icon and name, where it is, and a star to keep it.
struct LocationRow: View {
    let path: String
    let isFavorite: Bool
    let setFavorite: (Bool) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(FileManager.default.displayName(atPath: path))
                    .lineLimit(1)
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if isHovered || isFavorite {
                Button {
                    setFavorite(!isFavorite)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from favorites (⌘D)" : "Add to favorites (⌘D)")
            }
        }
        .padding(.vertical, 5)
        .onHover { isHovered = $0 }
    }
}
