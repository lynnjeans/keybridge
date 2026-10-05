import AppKit

enum Relaunch {
    /// Opens a new copy of SameKeys and quits this one: for changes read only
    /// at launch, such as the language and imported settings.
    @MainActor
    static func now() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }
}
