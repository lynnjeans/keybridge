import AppKit
import FinderSync

/// KeyBridge's Finder extension (KB-210): adds New › and Open in Terminal to
/// the menu of a folder's background, as on Windows.
///
/// It only builds the menu. Being sandboxed, it cannot write into the user's
/// folders, so each choice goes to KeyBridge as a `keybridge://` URL.
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Every folder: the menu belongs wherever a Finder window can be.
        FIFinderSyncController.default().directoryURLs = [URL(filePath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // Only on empty space, as on Windows; selected items keep Finder's menu.
        guard menuKind == .contextualMenuForContainer else { return nil }
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
        return menu
    }

    @objc private func createDocument(_ sender: NSMenuItem) {
        guard NewDocument.allCases.indices.contains(sender.tag), let folder = targetFolder else { return }
        send(.new(NewDocument.allCases[sender.tag], folder: folder))
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        guard let folder = targetFolder else { return }
        send(.openTerminal(folder: folder))
    }

    /// The folder whose background was clicked.
    private var targetFolder: URL? {
        FIFinderSyncController.default().targetedURL()
    }

    /// Hands the request to KeyBridge, launching it if needed, without
    /// bringing it to the front: the new file appears in Finder.
    private func send(_ request: FinderMenuRequest) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(request.url, configuration: configuration)
    }
}
