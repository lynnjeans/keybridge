import Foundation

/// Decides which folder a Finder window is showing from what its
/// Accessibility tree exposes (KB-214). Pure: `FinderFolder` reads the tree,
/// this only chooses, so every case measured on a real Finder is a unit test.
///
/// Finder does not say which folder a window shows — its `AXDocument` is
/// empty on macOS 26 — but the window's title is that folder's name, and the
/// path bar and the items in the view carry file URLs. Neither is the answer
/// on its own:
/// - The path bar follows the **selection**: select a file or a folder and its
///   last segment becomes that item, in every view.
/// - Items in Recents, a search or Applications (which merges
///   `/Applications` and `/System/Applications`) come from several folders,
///   and column view lists every column from the disk down.
///
/// So a folder counts only if it carries the window's title, and where more
/// than one folder could be meant the answer is nil: a box that opens empty
/// costs a keystroke, one that opens on the wrong folder sends the person
/// somewhere they did not ask to go.
enum FinderFolderPicker {
    /// One segment of the path bar: the name Finder shows, and where it
    /// points, nil when that is not a file path (Network's `nwnode:` segments).
    struct Crumb: Equatable {
        let name: String
        let path: String?
    }

    /// - Parameters:
    ///   - title: the window's title, the shown folder's name as Finder
    ///     displays it.
    ///   - crumbs: the path bar, outermost first; empty when it is hidden,
    ///     which is macOS's default.
    ///   - itemPaths: paths of items listed in the view, in any order.
    ///   - names: the names a folder may be shown under. The path bar's own
    ///     text is Finder's, but an item's parent has only a path, and
    ///     KeyBridge may run in another language than Finder — a mismatch
    ///     only leaves the box empty.
    ///   - isFolder: whether a path is a folder that exists.
    static func folder(
        title: String,
        crumbs: [Crumb],
        itemPaths: [String],
        names: (String) -> Set<String>,
        isFolder: (String) -> Bool
    ) -> String? {
        let title = comparable(title)
        guard !title.isEmpty else { return nil }
        // The deepest segment with the window's name; anything below it is
        // the selection. The one case this gets wrong is a selected folder
        // named like the folder it is in (`Foo/Foo`): the box then opens one
        // level too deep, which is rare and still next to where they are.
        if let path = crumbs.last(where: { comparable($0.name) == title && $0.path != nil })?.path, isFolder(path) {
            return path
        }
        // Without the path bar: the folder the items are in, if exactly one
        // of them carries the title. In column view that picks the column
        // being looked at; in Recents or a search none does.
        let parents = Set(itemPaths.map { ($0 as NSString).deletingLastPathComponent })
        let matches = parents.filter { names($0).map(comparable).contains(title) }
        guard matches.count == 1, let path = matches.first, isFolder(path) else { return nil }
        return path
    }

    /// Finder writes a name in the path bar with no-break spaces
    /// ("iCloud\u{A0}Drive") and in the window title with ordinary ones.
    /// (Composed and decomposed accents need nothing: Swift compares strings
    /// by canonical equivalence.)
    static func comparable(_ name: String) -> String {
        name.replacingOccurrences(of: "\u{A0}", with: " ")
    }
}
