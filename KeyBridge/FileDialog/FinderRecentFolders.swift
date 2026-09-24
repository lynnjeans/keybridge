import Foundation

/// Finder's Go › Recent Folders: the last ten folders Finder showed, most
/// recent first, which Finder keeps in its own preferences (`FXRecentFolders`)
/// and updates as you browse. KeyBridge reads it rather than watching Finder
/// itself.
enum FinderRecentFolders {
    /// Paths of the folders that still exist, most recent first.
    static func paths() -> [String] {
        let domain = BuiltInRules.finderID as CFString
        CFPreferencesAppSynchronize(domain)
        guard let entries = CFPreferencesCopyAppValue("FXRecentFolders" as CFString, domain) as? [[String: Any]] else {
            return []
        }
        return entries.compactMap { entry in
            guard let bookmark = entry["file-bookmark"] as? Data else { return nil }
            var isStale = false
            // Without UI or mounting: a folder on a server that is not
            // connected is skipped rather than prompting to connect.
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                     relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
            let path = url.path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
    }
}
