import Foundation

/// Whether KeyBridge runs from somewhere an update can replace it (KB-101).
///
/// An app opened straight from its disk image, or from Downloads before it
/// was ever moved, runs from a read-only disk image or from a random
/// read-only copy macOS makes for it ("App Translocation"). Sparkle cannot
/// replace either, so updates wait until KeyBridge is in Applications.
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

    /// What the user needs to do, or nil when nothing.
    var advice: String? {
        switch self {
        case .updatable:
            nil
        case .diskImage:
            String(localized: "KeyBridge is running from its disk image, where it cannot be updated. Drag it to the Applications folder and open it from there.")
        case .translocated:
            String(localized: "KeyBridge cannot be updated from the folder it was downloaded to. Move it to the Applications folder and open it from there.")
        }
    }
}
