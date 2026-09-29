import AppKit
import OSLog

/// Offers to move KeyBridge into the Applications folder when it runs from
/// somewhere else, and does the move (KB-233).
///
/// People coming from Windows often open the app straight from its disk
/// image or from Downloads. It works there for a while, but cannot update
/// itself, and is gone once the disk image is ejected. Rather than leave
/// them to find the Applications folder, KeyBridge copies itself there,
/// opens the copy and quits, as many Mac apps do.
@MainActor
enum MoveToApplications {
    /// Remembers "Do Not Move" for a folder other than the disk image.
    static let declinedKey = "moveToApplicationsDeclined"

    /// Asks at launch when `location` calls for it. Returns true when the
    /// move is under way and this copy is about to quit, in which case the
    /// caller should start nothing.
    static func offerAtLaunch(location: InstallLocation, defaults: UserDefaults = .standard) -> Bool {
        let bundle = Bundle.main.bundleURL
        #if DEBUG
        // Debug builds run from the build folder; only asked when testing this.
        guard ProcessInfo.processInfo.environment["KB_DEBUG_MOVE_OFFER"] != nil else { return false }
        #endif
        guard location.offersMove(path: bundle.path, homeDirectory: NSHomeDirectory(),
                                  declined: defaults.bool(forKey: declinedKey)) else { return false }
        return offer(location: location, defaults: defaults)
    }

    /// Asks, and moves if the user agrees. Also used by "Check for Updates…",
    /// which cannot work from a disk image or a translocated copy.
    @discardableResult
    static func offer(location: InstallLocation, defaults: UserDefaults = .standard) -> Bool {
        Logger.updates.notice("Offering to move to Applications from \(String(describing: location), privacy: .public)")
        WindowID.activateKeyBridge()
        let alert = NSAlert()
        alert.messageText = String(localized: "Move KeyBridge to the Applications folder?")
        alert.informativeText = String(localized: "KeyBridge can update itself there, and keeps working after you eject the disk image or clean up Downloads.")
        alert.addButton(withTitle: String(localized: "Move to Applications Folder"))
        alert.addButton(withTitle: String(localized: "Do Not Move"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            Logger.updates.notice("Move declined")
            // From a disk image the question comes back next time on purpose.
            if location == .updatable { defaults.set(true, forKey: declinedKey) }
            return false
        }
        do {
            try move()
            return true
        } catch {
            Logger.updates.error("Move failed: \(error.localizedDescription, privacy: .public)")
            let failure = NSAlert(error: error)
            failure.messageText = String(localized: "KeyBridge could not be moved")
            failure.informativeText = String(localized: "Drag KeyBridge to the Applications folder yourself, then open it from there.")
                + "\n\n" + error.localizedDescription
            failure.runModal()
            return false
        }
    }

    /// Copies the app to Applications, then quits; a small shell script
    /// waits for that, opens the copy and ejects the disk image it came from.
    private static func move() throws {
        let files = FileManager.default
        let running = Bundle.main.bundleURL
        // A translocated copy is a read-only mirror; the original tells
        // whether it came from a disk image.
        let origin = originalURL(ofTranslocated: running) ?? running
        let folder = try destinationFolder()
        let destination = folder.appending(path: running.lastPathComponent, directoryHint: .isDirectory)
        Logger.updates.notice("Moving \(origin.path, privacy: .public) to \(destination.path, privacy: .public)")

        if files.fileExists(atPath: destination.path) {
            quitCopy(at: destination)
            // To the Trash rather than deleted, in case it was not ours to replace.
            try files.trashItem(at: destination, resultingItemURL: nil)
        }
        // ditto keeps the bundle exactly as signed: symlinks, extended
        // attributes and all.
        try run("/usr/bin/ditto", [running.path, destination.path])
        // The copy keeps the download's quarantine flag, and with it macOS
        // would translocate it again. The user has already agreed to open it.
        try? run("/usr/bin/xattr", ["-d", "-r", "com.apple.quarantine", destination.path])

        // A disk image is ejected once this copy has quit. A download is left
        // where it is: Downloads, Desktop and Documents are protected, and
        // touching them would put a "KeyBridge would like to access…" prompt
        // in the middle of setting up permissions.
        let volume = (try? origin.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeURLKey]))
        var eject = ""
        if volume?.volumeIsReadOnly == true, let url = volume?.volume, url.path.hasPrefix("/Volumes/") {
            eject = url.path
        }

        let script = """
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        /usr/bin/open "$2"
        [ -n "$3" ] && /usr/bin/hdiutil detach -quiet "$3"
        exit 0
        """
        let relaunch = Process()
        relaunch.executableURL = URL(filePath: "/bin/sh")
        relaunch.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), destination.path, eject]
        try relaunch.run()
        Logger.updates.notice("Moved; relaunching from Applications")
        NSApplication.shared.terminate(nil)
    }

    /// /Applications, or ~/Applications for a user who may not write there.
    private static func destinationFolder() throws -> URL {
        let system = URL(filePath: "/Applications", directoryHint: .isDirectory)
        if FileManager.default.isWritableFile(atPath: system.path) { return system }
        let user = URL(filePath: NSHomeDirectory()).appending(path: "Applications", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        return user
    }

    /// Quits a KeyBridge already running from the place being replaced.
    private static func quitCopy(at url: URL) {
        let path = url.standardizedFileURL.path
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where app.bundleURL?.standardizedFileURL.path == path {
            app.terminate()
            let deadline = Date.now.addingTimeInterval(3)
            while !app.isTerminated, Date.now < deadline {
                RunLoop.current.run(until: .now.addingTimeInterval(0.1))
            }
            if !app.isTerminated { app.forceTerminate() }
        }
    }

    /// Where a translocated copy really lives. The function is in the
    /// Security framework but not in its headers, so it is looked up by name;
    /// without it the copy's own path is used, and only the clean-up is lost.
    private static func originalURL(ofTranslocated url: URL) -> URL? {
        guard url.path.contains("/AppTranslocation/"),
              let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        typealias Function = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let original = unsafeBitCast(symbol, to: Function.self)
        return original(url as CFURL, nil)?.takeRetainedValue() as URL?
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedFailureReasonErrorKey: "\((tool as NSString).lastPathComponent) exited with \(process.terminationStatus)"
            ])
        }
    }
}
