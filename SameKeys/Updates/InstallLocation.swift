import Foundation

/// Whether SameKeys runs from somewhere an update can replace it (KB-101).
///
/// An app opened straight from its disk image, or from Downloads before it
/// was ever moved, runs from a read-only disk image or from a random
/// read-only copy macOS makes for it ("App Translocation"). Sparkle cannot
/// replace either, so updates wait until SameKeys is in Applications.
enum InstallLocation: Equatable {
    case updatable
    /// Opened from its disk image.
    case diskImage
    /// Moved into a read-only copy by macOS because it was never moved out
    /// of the folder it was downloaded to.
    case translocated

    init(bundleURL: URL) {
        let isReadOnly = (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        self.init(path: bundleURL.path, volumeIsReadOnly: isReadOnly)
    }

    init(path: String, volumeIsReadOnly: Bool) {
        // Translocated copies live on a read-only mount too, so this comes first.
        if path.contains("/AppTranslocation/") {
            self = .translocated
        } else if volumeIsReadOnly {
            self = .diskImage
        } else {
            self = .updatable
        }
    }

    /// Whether SameKeys should offer at launch to move itself into the
    /// Applications folder (KB-233).
    ///
    /// From a disk image or a translocated copy it cannot update itself and
    /// is gone once the disk image is ejected or Downloads is cleaned up, so
    /// the offer comes back on every launch. From any other folder it works,
    /// and a "Not Now" there is final.
    func offersMove(path: String, homeDirectory: String, declined: Bool) -> Bool {
        switch self {
        case .diskImage, .translocated:
            true
        case .updatable:
            !declined && !Self.isInApplicationsFolder(path: path, homeDirectory: homeDirectory)
        }
    }

    /// Whether the app is in /Applications or ~/Applications, or a folder
    /// inside either.
    static func isInApplicationsFolder(path: String, homeDirectory: String) -> Bool {
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        return ["/Applications/", home + "/Applications/"].contains { path.hasPrefix($0) }
    }

    /// Whether installing a copy of build `runningBuild` should replace the
    /// one already in Applications (nil: none there). Not when that one is
    /// newer: a disk image found again after SameKeys has updated itself
    /// must not take it back to an older version. The same build is replaced
    /// only when asked to (an explicit Install, which also repairs a damaged
    /// copy), not when installing silently from the disk image.
    static func replaces(installedBuild: String?, runningBuild: String, replacingSameBuild: Bool = true) -> Bool {
        guard let installedBuild else { return true }
        switch installedBuild.compare(runningBuild, options: .numeric) {
        case .orderedAscending: return true
        case .orderedSame: return replacingSameBuild
        case .orderedDescending: return false
        }
    }

    /// What the user needs to do, or nil when nothing.
    var advice: String? {
        switch self {
        case .updatable:
            nil
        case .diskImage:
            String(localized: "SameKeys is running from its disk image, where it cannot be updated. Drag it to the Applications folder and open it from there.")
        case .translocated:
            String(localized: "SameKeys cannot be updated from the folder it was downloaded to. Move it to the Applications folder and open it from there.")
        }
    }
}
