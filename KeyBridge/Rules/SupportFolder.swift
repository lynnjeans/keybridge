import Foundation

extension URL {
    /// `~/Library/Application Support/KeyBridge/`, where the configuration and
    /// the clipboard history live.
    static var keyBridgeSupport: URL {
        #if DEBUG
        // A fresh folder gives a first launch's settings and an example
        // clipboard history, for the website's screenshots (KB-105).
        if let path = ProcessInfo.processInfo.environment["KB_DEBUG_SUPPORT_FOLDER"] {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        #endif
        return applicationSupportDirectory.appending(path: "KeyBridge")
    }
}
