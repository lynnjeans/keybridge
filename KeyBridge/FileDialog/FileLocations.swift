import Foundation
import Observation

/// The favorite and recent folders the recent locations list offers
/// (KB-219), kept across launches.
///
/// Recent folders are KeyBridge's own history, fed from two places: Finder's
/// Go › Recent Folders, which Finder keeps as you browse but only ten deep,
/// and every folder KeyBridge itself took a dialog, the path box or Finder
/// to. Keeping a copy lets the list be longer than Finder's ten.
@MainActor
@Observable
final class FileLocations {
    /// One row of the list.
    struct Location: Identifiable, Hashable, Sendable {
        enum Kind: Sendable { case favorite, finderWindow, recent }
        let path: String
        let kind: Kind
        var id: String { path }
    }

    /// Folders the person pinned, in the order they were added.
    private(set) var favorites: [String]

    /// Recent folders, most recent first, kept up to the longest list the
    /// setting allows so that raising the limit shows more at once.
    private(set) var history: [String]

    /// How many recent folders the list shows.
    var recentLimit: Int {
        didSet {
            // Correct whether or not assigning here runs this observer again.
            let clamped = Self.clamp(recentLimit)
            if clamped != recentLimit { recentLimit = clamped }
            defaults.set(clamped, forKey: Keys.recentLimit)
        }
    }

    static let limits = 5...30
    static let defaultLimit = 10

    /// The newest of Finder's recent folders when they were last merged in,
    /// so the next merge takes only what Finder added since.
    @ObservationIgnored private var finderTop: String?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let favorites = "fileDialog.favorites"
        static let history = "fileDialog.history"
        static let recentLimit = "fileDialog.recentLimit"
        static let finderTop = "fileDialog.finderTop"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = defaults.stringArray(forKey: Keys.favorites) ?? []
        history = defaults.stringArray(forKey: Keys.history) ?? []
        finderTop = defaults.string(forKey: Keys.finderTop)
        let limit = defaults.object(forKey: Keys.recentLimit) as? Int ?? Self.defaultLimit
        recentLimit = Self.clamp(limit)
    }

    private static func clamp(_ limit: Int) -> Int {
        min(max(limit, limits.lowerBound), limits.upperBound)
    }

    // MARK: - Recent folders

    /// Puts a folder KeyBridge went to at the top of the history.
    func record(_ path: String) {
        history = Self.recording(path, in: history)
        defaults.set(history, forKey: Keys.history)
    }

    /// Takes in what Finder added to its recent folders since the last time.
    /// - Parameter finder: Finder's recent folders, most recent first.
    func mergeFinder(_ finder: [String]) {
        history = Self.merging(finder: finder, into: history, previousTop: finderTop)
        finderTop = finder.first
        defaults.set(history, forKey: Keys.history)
        defaults.set(finderTop, forKey: Keys.finderTop)
    }

    /// Empties the history. Finder's recent folders as they are now count as
    /// seen, so they do not come straight back; only folders Finder shows
    /// from here on are added.
    func clearHistory(finderTop: String?) {
        history = []
        self.finderTop = finderTop
        defaults.set(history, forKey: Keys.history)
        defaults.set(finderTop, forKey: Keys.finderTop)
    }

    // MARK: - Favorites

    func isFavorite(_ path: String) -> Bool {
        favorites.contains(path)
    }

    func setFavorite(_ path: String, _ isFavorite: Bool) {
        favorites.removeAll { $0 == path }
        if isFavorite { favorites.append(path) }
        defaults.set(favorites, forKey: Keys.favorites)
    }

    // MARK: - The list

    /// The rows of the list: favorites, then the folders open in Finder, then
    /// recent folders up to the limit. A folder appears once, in the first
    /// section it belongs to, and only while it exists.
    func entries(finderWindows: [String], exists: (String) -> Bool) -> [Location] {
        Self.entries(favorites: favorites, finderWindows: finderWindows, history: history,
                     limit: recentLimit, exists: exists)
    }

    // MARK: - Pure rules, for the tests

    /// The longest history kept.
    static var capacity: Int { limits.upperBound }

    static func recording(_ path: String, in history: [String]) -> [String] {
        Array(([path] + history.filter { $0 != path }).prefix(capacity))
    }

    /// Finder's list is newest first. What sits above the folder that was
    /// its newest last time is new since then; with no such folder in the
    /// list any more (Finder moved on by more than ten) all of it is. New
    /// folders go on top in Finder's order.
    static func merging(finder: [String], into history: [String], previousTop: String?) -> [String] {
        let fresh: ArraySlice<String>
        if let previousTop, let index = finder.firstIndex(of: previousTop) {
            fresh = finder[..<index]
        } else {
            fresh = finder[...]
        }
        return fresh.reversed().reduce(history) { recording($1, in: $0) }
    }

    static func entries(
        favorites: [String], finderWindows: [String], history: [String], limit: Int, exists: (String) -> Bool
    ) -> [Location] {
        var seen = Set<String>()
        func take(_ paths: [String], as kind: Location.Kind, limit: Int = .max) -> [Location] {
            var result: [Location] = []
            for path in paths where result.count < limit && !seen.contains(path) && exists(path) {
                seen.insert(path)
                result.append(Location(path: path, kind: kind))
            }
            return result
        }
        return take(favorites, as: .favorite)
            + take(finderWindows, as: .finderWindow)
            + take(history, as: .recent, limit: limit)
    }
}
