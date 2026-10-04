/// Finds history items as the user types: every word of the query has to
/// appear, in any order and any case, in the item's text or file name. It
/// runs on every key press, over a few hundred items at most, so a plain
/// scan is instant.
enum ClipboardSearch {
    static func filter(_ items: [ClipboardItem], _ query: String) -> [ClipboardItem] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let haystack = [item.text, item.fileURL?.lastPathComponent]
                .compactMap { $0?.lowercased() }
                .joined(separator: "\n")
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    /// Pinned items first, then the rest, each newest first.
    static func ordered(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter(\.isPinned) + items.filter { !$0.isPinned }
    }
}
