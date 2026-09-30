import AppKit
import OSLog

/// Installs KeyBridge in the Applications folder when it runs from somewhere
/// else (KB-233).
///
/// The disk image holds only KeyBridge and says "Double-click KeyBridge to
/// install": opened from there, it copies itself to Applications without
/// asking, opens the copy, quits and ejects the disk image, all before the
/// app itself starts (`installFromDiskImageBeforeLaunch`). Opened from
/// anywhere else outside Applications, such as Downloads, it asks first.
/// There it works for a while, but cannot update itself.
@MainActor
enum MoveToApplications {
    /// Remembers "Not Now" for a folder other than the disk image.
    static let declinedKey = "moveToApplicationsDeclined"

    /// Opened from its disk image, installs and hands over to the installed
    /// copy before the app starts. Returns true when the caller should exit
    /// at once (KB-235).
    ///
    /// Nothing may ask macOS about permissions first: a check from the disk
    /// image left Input Monitoring "denied" for the installed copy, with no
    /// row in System Settings to switch on. The same build already installed
    /// is opened rather than copied again, which also keeps a second launch
    /// from the disk image, as happens right after Gatekeeper's dialog, from
    /// replacing the copy the first one just opened. If the install fails,
    /// the app starts from the disk image and `offerAtLaunch` says why.
    static func installFromDiskImageBeforeLaunch() -> Bool {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["KB_DEBUG_MOVE_OFFER"] != nil else { return false }
        #endif
        guard isOnDiskImage(origin(of: Bundle.main.bundleURL)) else { return false }
        Logger.updates.notice("Opened from its disk image: installing before launch")
        do {
            try move(replacingSameBuild: false)
            return true
        } catch {
            Logger.updates.error("Install before launch failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Installs, or asks to, at launch when `location` calls for it. Returns
    /// true when the install is under way and this copy is about to quit, in
    /// which case the caller should start nothing.
    static func offerAtLaunch(location: InstallLocation, defaults: UserDefaults = .standard) -> Bool {
        let bundle = Bundle.main.bundleURL
        #if DEBUG
        // Debug builds run from the build folder; only asked when testing this.
        guard ProcessInfo.processInfo.environment["KB_DEBUG_MOVE_OFFER"] != nil else { return false }
        #endif
        guard location.offersMove(path: bundle.path, homeDirectory: NSHomeDirectory(),
                                  declined: defaults.bool(forKey: declinedKey)) else { return false }
        // Double-clicking KeyBridge in its disk image is what the window
        // asks for to install it, so that is taken as the answer.
        if isOnDiskImage(origin(of: bundle)) {
            Logger.updates.notice("Opened from its disk image: installing")
            return install()
        }
        return offer(location: location, defaults: defaults)
    }

    /// Asks, and installs if the user agrees. Also used by "Check for Updates…",
    /// which cannot work from a disk image or a translocated copy.
    @discardableResult
    static func offer(location: InstallLocation, defaults: UserDefaults = .standard) -> Bool {
        Logger.updates.notice("Offering to install in Applications from \(String(describing: location), privacy: .public)")
        WindowID.activateKeyBridge()
        let alert = NSAlert()
        alert.messageText = String(localized: "Install KeyBridge in the Applications folder?")
        alert.informativeText = String(localized: "KeyBridge can update itself there, and keeps working after you eject the disk image or clean up Downloads.")
        alert.addButton(withTitle: String(localized: "Install"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            Logger.updates.notice("Install declined")
            // From a disk image the question comes back next time on purpose.
            if location == .updatable { defaults.set(true, forKey: declinedKey) }
            return false
        }
        return install()
    }

    /// Installs and quits, or explains what went wrong and returns false.
    private static func install() -> Bool {
        do {
            try move(replacingSameBuild: true)
            NSApplication.shared.terminate(nil)
            return true
        } catch {
            Logger.updates.error("Install failed: \(error.localizedDescription, privacy: .public)")
            let failure = NSAlert(error: error)
            failure.messageText = String(localized: "KeyBridge could not be installed")
            failure.informativeText = String(localized: "Drag KeyBridge to the Applications folder yourself, then open it from there.")
                + "\n\n" + error.localizedDescription
            failure.runModal()
            return false
        }
    }

    /// Copies the app to Applications and starts a small shell script that
    /// waits for this process to end, opens the copy and ejects the disk
    /// image it came from. The caller then quits.
    private static func move(replacingSameBuild: Bool) throws {
        let files = FileManager.default
        let running = Bundle.main.bundleURL
        let source = origin(of: running)
        let folder = try destinationFolder()
        let destination = folder.appending(path: running.lastPathComponent, directoryHint: .isDirectory)

        let installed = files.fileExists(atPath: destination.path) ? buildNumber(of: destination) ?? "" : nil
        if InstallLocation.replaces(installedBuild: installed, runningBuild: buildNumber(of: running) ?? "",
                                    replacingSameBuild: replacingSameBuild) {
            Logger.updates.notice("Installing \(source.path, privacy: .public) as \(destination.path, privacy: .public)")
            if installed != nil {
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
        } else {
            // An older disk image found again after KeyBridge has updated
            // itself, or this build already installed: that copy stays and
            // is the one opened.
            Logger.updates.notice("KeyBridge build \(installed ?? "", privacy: .public) is already in \(folder.path, privacy: .public); opening it")
        }

        // A disk image is ejected once this copy has quit. A download is left
        // where it is: Downloads, Desktop and Documents are protected, and
        // touching them would put a "KeyBridge would like to access…" prompt
        // in the middle of setting up permissions.
        let eject = isOnDiskImage(source) ? volumePath(of: source) ?? "" : ""

        let script = """
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        /usr/bin/open "$2"
        [ -z "$3" ] && exit 0
        # Right after KeyBridge quits, the disk image can still be busy (Spotlight
        # indexing it, Finder's window on it), so detaching is retried, and the
        # last try forced: the image is read-only, nothing on it can be lost.
        for force in "" "" "" "" "" "" "" "" "" -force; do
            if /usr/bin/hdiutil detach -quiet $force "$3" 2>/dev/null; then
                /usr/bin/logger -t KeyBridge "Ejected $3"
                exit 0
            fi
            /bin/sleep 1
        done
        /usr/bin/logger -t KeyBridge "Could not eject $3"
        """
        let relaunch = Process()
        relaunch.executableURL = URL(filePath: "/bin/sh")
        relaunch.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), destination.path, eject]
        try relaunch.run()
        Logger.updates.notice("Installed; opening it from \(folder.path, privacy: .public)")
    }

    /// Where the app really is: a translocated copy is a read-only mirror of
    /// it, which says nothing about whether it came from a disk image.
    private static func origin(of bundle: URL) -> URL {
        originalURL(ofTranslocated: bundle) ?? bundle
    }

    private static func isOnDiskImage(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly == true && volumePath(of: url) != nil
    }

    /// The mounted volume holding `url`, when it is one under /Volumes.
    private static func volumePath(of url: URL) -> String? {
        guard let volume = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume,
              volume.path.hasPrefix("/Volumes/") else { return nil }
        return volume.path
    }

    private static func buildNumber(of bundle: URL) -> String? {
        let info = NSDictionary(contentsOf: bundle.appending(path: "Contents/Info.plist"))
        return info?["CFBundleVersion"] as? String
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
