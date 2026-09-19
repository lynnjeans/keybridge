import Foundation
import OSLog

/// Keeps the clipboard history on disk, in
/// `~/Library/Application Support/KeyBridge/Clipboard/`.
///
/// Each copy's contents go in a file of their own, written once when the
/// copy is made and deleted when it leaves the history; a small index holds
/// the order, dates and pins. Copying something new therefore writes one
/// file and the index, however large the rest of the history is. The folder
/// is readable by the user only.
struct ClipboardStore: Sendable {
    let folder: URL

    static var defaultFolder: URL {
        URL.keyBridgeSupport.appending(path: "Clipboard")
    }

    init(folder: URL = Self.defaultFolder) {
        self.folder = folder
    }

    private var indexURL: URL { folder.appending(path: "index.json") }
    private var itemsFolder: URL { folder.appending(path: "items") }

    private func contentsURL(_ id: UUID) -> URL {
        itemsFolder.appending(path: "\(id.uuidString).plist")
    }

    /// What the index records per item; the contents live in their file.
    private struct Entry: Codable {
        var id: UUID
        var date: Date
        var sourceBundleID: String?
        var isPinned: Bool
    }

    private struct Index: Codable {
        var version = 1
        var items: [Entry]
    }

    /// The saved history, newest first. Entries whose contents file is
    /// missing or unreadable are dropped; nothing here ever fails loudly.
    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        guard let index = try? JSONDecoder().decode(Index.self, from: data) else {
            Logger.clipboard.error("Clipboard index unreadable; starting empty")
            return []
        }
        return index.items.compactMap { entry in
            guard let data = try? Data(contentsOf: contentsURL(entry.id)),
                  let contents = try? PropertyListDecoder().decode([String: Data].self, from: data) else { return nil }
            return ClipboardItem(
                id: entry.id, date: entry.date, sourceBundleID: entry.sourceBundleID,
                contents: contents, isPinned: entry.isPinned
            )
        }
    }

    /// Makes the disk match `items`: writes contents that are new, deletes
    /// those no longer kept, and rewrites the index.
    func save(_ items: [ClipboardItem]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: itemsFolder, withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)

        let kept = Set(items.map(\.id))
        let onDisk = (try? manager.contentsOfDirectory(at: itemsFolder, includingPropertiesForKeys: nil)) ?? []
        var present: Set<UUID> = []
        for url in onDisk {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), kept.contains(id) else {
                try? manager.removeItem(at: url)
                continue
            }
            present.insert(id)
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        for item in items where !present.contains(item.id) {
            try encoder.encode(item.contents).write(to: contentsURL(item.id), options: .atomic)
        }

        let index = Index(items: items.map {
            Entry(id: $0.id, date: $0.date, sourceBundleID: $0.sourceBundleID, isPinned: $0.isPinned)
        })
        try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
    }
}
