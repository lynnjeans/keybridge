import AppKit
import OSLog

/// Carries out the file dialog rules (KB-217, KB-219): going to Finder's
/// folder, and the list of favorite and recent folders.
@MainActor
final class QuickSwitch {
    let locations: FileLocations
    private let panel: LocationsPanelController

    init(locations: FileLocations) {
        self.locations = locations
        panel = LocationsPanelController(locations: locations)
    }

    func perform(_ action: FileDialogAction) {
        switch action {
        case .finderFolder:
            guard let path = FinderFolder.frontWindowPath() ?? FinderRecentFolders.paths().first else {
                Logger.fileDialog.notice("No Finder folder to go to")
                NSSound.beep()
                return
            }
            FileDialog.jump(to: path) { [locations] in locations.record($0) }
        case .recentLocations:
            showList()
        }
    }

    /// Takes in what Finder added to its recent folders. Called as Finder
    /// leaves the front, so the history keeps roughly the order things
    /// happened in, and before the list opens.
    func mergeFinderRecents() {
        locations.mergeFinder(FinderRecentFolders.paths())
    }

    /// Empties the history; Finder's own list is left as it is.
    func clearHistory() {
        locations.clearHistory(finderTop: FinderRecentFolders.paths().first)
    }

    /// Over a dialog, the chosen folder is jumped to; over Finder, it is
    /// opened, as the path box opens one.
    private func showList() {
        mergeFinderRecents()
        let inFinder = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == BuiltInRules.finderID
        let entries = locations.entries(finderWindows: FinderFolder.windowPaths()) { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        panel.show(entries) { [locations] path in
            if inFinder {
                NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
                locations.record(path)
            } else {
                // A moment for the dialog to take the keyboard back from the
                // list before ⌘⇧G is sent to it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    FileDialog.jump(to: path) { locations.record($0) }
                }
            }
        }
    }
}
