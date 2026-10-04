import Foundation
import Testing

/// Favorite and recent folders for the recent locations list (KB-219).
@MainActor
@Suite struct FileLocationsTests {
    private func store() -> (FileLocations, UserDefaults) {
        let defaults = UserDefaults(suiteName: "FileLocationsTests-\(UUID().uuidString)")!
        return (FileLocations(defaults: defaults), defaults)
    }

    // MARK: - History

    @Test func aVisitGoesOnTopOnce() {
        #expect(FileLocations.recording("/b", in: ["/a", "/b", "/c"]) == ["/b", "/a", "/c"])
        #expect(FileLocations.recording("/d", in: ["/a"]) == ["/d", "/a"])
    }

    @Test func historyIsCappedAtTheLongestList() {
        let long = (1...40).map { "/f\($0)" }
        let history = long.reduce([String]()) { FileLocations.recording($1, in: $0) }
        #expect(history.count == FileLocations.capacity)
        #expect(history.first == "/f40")
    }

    /// Only what Finder added since last time goes on top, in Finder's order.
    @Test func finderRecentsMergeOnlyWhatIsNew() {
        let history = ["/kb-jump", "/old"]
        let merged = FileLocations.merging(finder: ["/new2", "/new1", "/seen", "/older"], into: history, previousTop: "/seen")
        #expect(merged == ["/new2", "/new1", "/kb-jump", "/old"])
    }

    @Test func theFirstMergeTakesAllOfFinders() {
        #expect(FileLocations.merging(finder: ["/a", "/b"], into: [], previousTop: nil) == ["/a", "/b"])
        // Finder moved on by more than its ten: the old top is gone.
        #expect(FileLocations.merging(finder: ["/x", "/y"], into: ["/z"], previousTop: "/gone") == ["/x", "/y", "/z"])
    }

    @Test func mergingTheSameListTwiceChangesNothing() {
        let (locations, _) = store()
        locations.mergeFinder(["/a", "/b"])
        locations.record("/jumped")
        locations.mergeFinder(["/a", "/b"])
        #expect(locations.history == ["/jumped", "/a", "/b"])
    }

    /// Cleared stays cleared: Finder's list as it was does not come back.
    @Test func clearingForgetsFindersCurrentList() {
        let (locations, _) = store()
        locations.mergeFinder(["/a", "/b"])
        locations.clearHistory(finderTop: "/a")
        locations.mergeFinder(["/a", "/b"])
        #expect(locations.history.isEmpty)
        locations.mergeFinder(["/c", "/a", "/b"])
        #expect(locations.history == ["/c"])
    }

    // MARK: - Settings

    @Test func theLimitIsTenAndStaysInRange() {
        let (locations, defaults) = store()
        #expect(locations.recentLimit == 10)
        locations.recentLimit = 100
        #expect(locations.recentLimit == FileLocations.limits.upperBound)
        locations.recentLimit = 1
        #expect(locations.recentLimit == FileLocations.limits.lowerBound)
        locations.recentLimit = 12
        #expect(FileLocations(defaults: defaults).recentLimit == 12)
    }

    @Test func favoritesAreKeptInOrderAndOnce() {
        let (locations, defaults) = store()
        locations.setFavorite("/a", true)
        locations.setFavorite("/b", true)
        locations.setFavorite("/a", true)
        #expect(locations.favorites == ["/b", "/a"])
        locations.setFavorite("/b", false)
        #expect(FileLocations(defaults: defaults).favorites == ["/a"])
    }

    // MARK: - The list

    @Test func eachFolderAppearsOnceInTheFirstSectionItBelongsTo() {
        let entries = FileLocations.entries(
            favorites: ["/fav"], finderWindows: ["/open", "/fav"], history: ["/open", "/r1", "/fav", "/r2", "/r3"],
            limit: 2, exists: { _ in true }
        )
        #expect(entries.map(\.path) == ["/fav", "/open", "/r1", "/r2"])
        #expect(entries.map(\.kind) == [.favorite, .finderWindow, .recent, .recent])
    }

    @Test func foldersThatAreGoneAreLeftOut() {
        let entries = FileLocations.entries(favorites: ["/gone"], finderWindows: [], history: ["/gone", "/here"],
                                            limit: 10, exists: { $0 != "/gone" })
        #expect(entries.map(\.path) == ["/here"])
    }
}
