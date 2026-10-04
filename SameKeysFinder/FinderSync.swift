import AppKit
import FinderSync
import OSLog

/// SameKeys's Finder extension: adds New › and Open in Terminal to the menu
/// of a folder's background (KB-210), and Copy Path (KB-212) and Add to
/// SameKeys Favorites (KB-220) to that and to selected items, as on Windows.
///
/// It only builds the menu. Being sandboxed, it cannot write into the user's
/// folders, so New and Open in Terminal go to SameKeys as a `samekeys://`
/// URL; Copy Path only touches the pasteboard, which needs no entitlement,
/// so it runs right here and works even when SameKeys isn't running.
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Every folder: the menu belongs wherever a Finder window can be.
        FIFinderSyncController.default().directoryURLs = [URL(filePath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .contextualMenuForContainer:
            return containerMenu()
        case .contextualMenuForItems:
            return itemsMenu()
        default:
            return nil
        }
    }

    /// The menu on a folder's empty background: New ›, Open in Terminal, and
    /// Copy Path for the folder itself.
    private func containerMenu() -> NSMenu {
        let menu = NSMenu()

        let new = NSMenu()
        for document in NewDocument.allCases where document.isAvailable {
            let item = NSMenuItem(title: document.menuTitle, action: #selector(createDocument(_:)), keyEquivalent: "")
            // Finder copies the menu before showing it and keeps only the
            // tag, not a represented object.
            item.tag = NewDocument.allCases.firstIndex(of: document)!
            item.image = document.icon
            new.addItem(item)
        }
        let newItem = NSMenuItem(title: FinderMenuTitle.new, action: nil, keyEquivalent: "")
        newItem.submenu = new
        // A symbol, as Finder draws its own New Folder item.
        newItem.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
        menu.addItem(newItem)

        let terminal = NSMenuItem(title: FinderMenuTitle.openInTerminal,
                                  action: #selector(openTerminal(_:)), keyEquivalent: "")
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let icon = NSWorkspace.shared.icon(forFile: app.path(percentEncoded: false))
            icon.size = NSSize(width: 16, height: 16)
            terminal.image = icon
        }
        menu.addItem(terminal)
        // No separator: Finder on macOS 26 shows one an extension adds as an
        // empty row (KB-256).
        menu.addItem(copyPathItem())
        menu.addItem(addFavoriteItem())
        return menu
    }

    /// The menu on one or more selected items: Copy Path, and Add to
    /// SameKeys Favorites when a folder is among them. SameKeys checks
    /// again and leaves out packages.
    private func itemsMenu() -> NSMenu? {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return nil }
        let menu = NSMenu()
        menu.addItem(copyPathItem())
        let folders = urls.filter(Self.isFolder)
        Logger(subsystem: "com.samekeys.SameKeys.Finder", category: "menu")
            .info("items menu: \(urls.count, privacy: .public) selected, \(folders.count, privacy: .public) folders")
        if !folders.isEmpty { menu.addItem(addFavoriteItem()) }
        return menu
    }

    /// Finder ends a folder's URL in a slash; failing that, the file's own
    /// metadata is asked, which the sandbox may or may not allow.
    private static func isFolder(_ url: URL) -> Bool {
        url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private func addFavoriteItem() -> NSMenuItem {
        let item = NSMenuItem(title: FinderMenuTitle.addFavorite, action: #selector(addFavorite(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        return item
    }

    private func copyPathItem() -> NSMenuItem {
        let item = NSMenuItem(title: FinderMenuTitle.copyPath, action: #selector(copyPath(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        return item
    }

    @objc private func createDocument(_ sender: NSMenuItem) {
        guard NewDocument.allCases.indices.contains(sender.tag), let folder = targetFolder else { return }
        send(.new(NewDocument.allCases[sender.tag], folder: folder))
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        guard let folder = targetFolder else { return }
        send(.openTerminal(folder: folder))
    }

    /// Copies the selection's paths, or the background folder's own path
    /// when nothing is selected, one per line.
    @objc private func copyPath(_ sender: NSMenuItem) {
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        let urls = selected.isEmpty ? [targetFolder].compactMap { $0 } : selected
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(CopyPath.text(for: urls), forType: .string)
    }

    /// The selected folders, or the background folder itself when nothing
    /// is selected.
    @objc private func addFavorite(_ sender: NSMenuItem) {
        let selected = (FIFinderSyncController.default().selectedItemURLs() ?? []).filter(Self.isFolder)
        let folders = selected.isEmpty ? [targetFolder].compactMap { $0 } : selected
        guard !folders.isEmpty else { return }
        send(.addFavorites(folders: folders))
    }

    /// The folder whose background was clicked.
    private var targetFolder: URL? {
        FIFinderSyncController.default().targetedURL()
    }

    /// Hands the request to SameKeys, launching it if needed, without
    /// bringing it to the front: the new file appears in Finder.
    private func send(_ request: FinderMenuRequest) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(request.url, configuration: configuration)
    }
}
