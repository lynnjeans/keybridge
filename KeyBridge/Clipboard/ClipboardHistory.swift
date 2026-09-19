import Foundation
import Observation

/// The copies KeyBridge has kept, newest first. Pinned items never count
/// against the limit and are never dropped.
@MainActor
@Observable
final class ClipboardHistory {
    private(set) var items: [ClipboardItem] = []

    /// How many unpinned items are kept.
    var limit: Int {
        didSet { trim() }
    }

    init(items: [ClipboardItem] = [], limit: Int = 200) {
        self.items = items
        self.limit = limit
        trim()
    }

    /// Adds a copy at the top. The same contents copied again move up
    /// instead of appearing twice, keeping their pin.
    func add(_ item: ClipboardItem) {
        var item = item
        if let index = items.firstIndex(where: { $0.hasSameContents(as: item) }) {
            item.isPinned = items[index].isPinned
            item.id = items[index].id
            items.remove(at: index)
        }
        items.insert(item, at: 0)
        trim()
    }

    func remove(_ id: ClipboardItem.ID) {
        items.removeAll { $0.id == id }
    }

    /// Empties the history, keeping pinned items.
    func clear() {
        items.removeAll { !$0.isPinned }
    }

    /// Drops the oldest unpinned items beyond the limit.
    private func trim() {
        var unpinned = 0
        items.removeAll { item in
            guard !item.isPinned else { return false }
            unpinned += 1
            return unpinned > limit
        }
    }
}
