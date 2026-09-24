import Foundation
import Testing

/// Which folder a Finder window is showing, from what its Accessibility tree
/// exposes (KB-214). Each case is a shape measured on Finder in macOS 26.
@Suite struct FinderFolderTests {
    private typealias Crumb = FinderFolderPicker.Crumb

    /// The path bar for `/Users/lei/<components…>`.
    private func crumbs(_ components: String...) -> [Crumb] {
        var path = "/Users/lei"
        var result = [Crumb(name: "Macintosh HD", path: "/"), Crumb(name: "Users", path: "/Users"),
                      Crumb(name: "lei", path: path)]
        for component in components {
            path += "/" + component
            result.append(Crumb(name: component, path: path))
        }
        return result
    }

    private func pick(
        title: String,
        crumbs: [Crumb] = [],
        items: [String] = [],
        folders: Set<String>? = nil,
        names: [String: String] = [:]
    ) -> String? {
        FinderFolderPicker.folder(
            title: title,
            crumbs: crumbs,
            itemPaths: items,
            names: { path in [names[path] ?? (path as NSString).lastPathComponent] },
            // By default every path that is not an item is a folder.
            isFolder: { folders?.contains($0) ?? !items.contains($0) }
        )
    }

    @Test func thePathBarsLastSegmentWhenNothingIsSelected() {
        #expect(pick(title: "Beta", crumbs: crumbs("Alpha", "Beta")) == "/Users/lei/Alpha/Beta")
    }

    @Test func aSelectedFileInThePathBarIsSkipped() {
        let bar = crumbs("Alpha", "Beta", "one.txt")
        #expect(pick(title: "Beta", crumbs: bar, folders: ["/Users/lei/Alpha/Beta"]) == "/Users/lei/Alpha/Beta")
    }

    /// The case taking the parent of anything that is not a folder would get
    /// wrong: a selected folder is a folder too.
    @Test func aSelectedFolderInThePathBarIsSkipped() {
        #expect(pick(title: "Alpha", crumbs: crumbs("Alpha", "Beta")) == "/Users/lei/Alpha")
    }

    /// Column view moves the window into a folder once it is selected: the
    /// title follows it, and so does the answer.
    @Test func columnViewFollowsTheSelectedFolder() {
        #expect(pick(title: "Beta", crumbs: crumbs("Alpha", "Beta")) == "/Users/lei/Alpha/Beta")
    }

    @Test func pathBarNamesWithNoBreakSpacesMatchTheTitle() {
        let icloud = "/Users/lei/Library/Mobile Documents/com~apple~CloudDocs"
        let bar = [Crumb(name: "iCloud\u{A0}Drive", path: icloud)]
        #expect(pick(title: "iCloud Drive", crumbs: bar) == icloud)
    }

    @Test func aSegmentThatIsNotAFilePathIsIgnored() {
        #expect(pick(title: "Network", crumbs: [Crumb(name: "Network", path: nil)]) == nil)
    }

    @Test func aFolderThatNoLongerExistsGivesNothing() {
        #expect(pick(title: "Beta", crumbs: crumbs("Alpha", "Beta"), folders: []) == nil)
    }

    // MARK: Path bar hidden, macOS's default

    @Test func theItemsFolderWhenThePathBarIsHidden() {
        let items = ["/Users/lei/Alpha/Beta/one.txt", "/Users/lei/Alpha/Beta/two.md"]
        #expect(pick(title: "Beta", items: items) == "/Users/lei/Alpha/Beta")
    }

    /// Column view lists several columns; the one named like the window is
    /// the folder.
    @Test func theColumnNamedLikeTheWindow() {
        let items = ["/Users/lei/Alpha", "/Users/lei/Documents",
                     "/Users/lei/Alpha/Beta", "/Users/lei/Alpha/a.txt",
                     "/Users/lei/Alpha/Beta/one.txt"]
        #expect(pick(title: "Beta", items: items, folders: ["/Users/lei", "/Users/lei/Alpha", "/Users/lei/Alpha/Beta"])
            == "/Users/lei/Alpha/Beta")
    }

    /// Recents lists files from all over; all of them from one folder must
    /// still not be taken for it.
    @Test func recentsGivesNothing() {
        let scattered = ["/Users/lei/Downloads/a.pdf", "/Users/lei/Documents/b.txt"]
        #expect(pick(title: "Recents", items: scattered) == nil)
        let oneFolder = ["/Users/lei/Downloads/a.pdf", "/Users/lei/Downloads/b.pdf"]
        #expect(pick(title: "Recents", items: oneFolder) == nil)
    }

    /// Applications merges `/Applications` and `/System/Applications`; with
    /// no path bar to say which, the box stays empty rather than guessing.
    @Test func twoFoldersWithTheWindowsNameGiveNothing() {
        let items = ["/Applications/Safari.app", "/System/Applications/Mail.app"]
        #expect(pick(title: "Applications", items: items) == nil)
    }

    /// Finder shows a folder under its localized name; the file system name
    /// is accepted too, since KeyBridge's language may differ from Finder's.
    @Test func aLocalizedFolderNameMatches() {
        let items = ["/Users/lei/Downloads/a.pdf"]
        #expect(pick(title: "下载", items: items, names: ["/Users/lei/Downloads": "下载"]) == "/Users/lei/Downloads")
    }

    @Test func anEmptyFolderWithoutThePathBarGivesNothing() {
        #expect(pick(title: "Empty") == nil)
    }

    @Test func anUntitledWindowGivesNothing() {
        #expect(pick(title: "", crumbs: [Crumb(name: "", path: "/")]) == nil)
    }
}
