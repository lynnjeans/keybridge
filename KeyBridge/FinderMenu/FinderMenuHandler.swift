import AppKit
import OSLog

/// Carries out what was chosen in the Finder extension's menu (KB-210).
@MainActor
enum FinderMenuHandler {
    /// Handles a `keybridge://finder/…` URL. Returns false for any other URL.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard let request = FinderMenuRequest(url: url) else { return false }
        switch request {
        case let .new(document, folder):
            guard isFolder(folder) else { return true }
            do {
                let file = try create(document, in: folder)
                Logger.finderMenu.notice("created \(document.rawValue, privacy: .public)")
                startRenaming(file)
            } catch {
                Logger.finderMenu.error("creating \(document.rawValue, privacy: .public) failed: \(error, privacy: .public)")
                NSSound.beep()
            }
        case let .openTerminal(folder):
            guard isFolder(folder) else { return true }
            openTerminal(at: folder)
        }
        return true
    }

    /// Creates a new file of `document`'s kind in `folder` under the first
    /// free name, never replacing one that exists.
    static func create(_ document: NewDocument, in folder: URL) throws -> URL {
        let files = FileManager.default
        let file = NewDocument.freeURL(for: document, in: folder) {
            files.fileExists(atPath: $0.path(percentEncoded: false))
        }
        switch document.source {
        case .empty:
            try Data().write(to: file, options: .withoutOverwriting)
        case let .bundled(name):
            guard let template = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Templates") else {
                throw CocoaError(.fileNoSuchFile)
            }
            try files.copyItem(at: template, to: file)
        case .appTemplate:
            guard let template = document.appTemplate else { throw CocoaError(.fileNoSuchFile) }
            try files.copyItem(at: template, to: file)
        }
        // A copy keeps its template's dates; a new file should read as new.
        let now = Date()
        try? files.setAttributes([.creationDate: now, .modificationDate: now], ofItemAtPath: file.path(percentEncoded: false))
        return file
    }

    /// Selects the new file in Finder and starts renaming it, as Windows
    /// does. Return renames in Finder; KeyBridge's own Enter-opens rule lets
    /// it through because KeyBridge stamps the events it posts.
    private static func startRenaming(_ file: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
        // Finder takes a moment to list a file that did not exist before and
        // to select it; a Return before that would rename whatever was
        // selected.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
                  AXIsProcessTrusted() else { return }
            for down in [true, false] {
                SyntheticEvent.key(KeyCombo(.returnKey), down: down)?.post(tap: .cgSessionEventTap)
            }
        }
    }

    /// Opens a Terminal window in `folder`, like Windows 11's Open in Terminal.
    private static func openTerminal(at folder: URL) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return
        }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: .init()) { _, error in
            if let error {
                Logger.finderMenu.error("opening Terminal failed: \(error, privacy: .public)")
            }
        }
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

extension Logger {
    static let finderMenu = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge",
        category: "finderMenu"
    )
}
