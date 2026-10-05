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
    /// opened, as the path box opens one. A pasted file (KB-268) is opened:
    /// by its app over Finder, by the dialog's Open button over an open
    /// dialog; a save dialog only goes to it and selects it.
    private func showList() {
        mergeFinderRecents()
        let inFinder = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == BuiltInRules.finderID
        let entries = locations.entries(finderWindows: FinderFolder.windowPaths()) { path in
            var isDirectory: ObjCBool = false
            // An app or a Keynote document is a directory on disk, but opening
            // it would launch it (KB-254).
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
                && !NSWorkspace.shared.isFilePackage(atPath: path)
        }
        let inSaveDialog = !inFinder && FileDialog.isSaveDialog() == true
        panel.show(entries, opensFiles: !inSaveDialog) { [locations] location in
            let path = location.path
            let isFile = location.kind == .pastedFile
            let folder = isFile ? (path as NSString).deletingLastPathComponent : path
            if inFinder {
                if isFile {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                } else {
                    guard !NSWorkspace.shared.isFilePackage(atPath: path) else { return }
                    NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
                }
                locations.record(folder)
            } else {
                // A moment for the dialog to take the keyboard back from the
                // list before ⌘⇧G is sent to it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if isFile && !inSaveDialog {
                        FileDialog.open(path) { _ in locations.record(folder) }
                    } else {
                        FileDialog.jump(to: path) { _ in locations.record(folder) }
                    }
                }
            }
        }
    }
}
