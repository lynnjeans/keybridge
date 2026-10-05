import AppKit

extension NSWindow.Level {
    /// Where SameKeys's own panels float (KB-268): above an app-modal open or
    /// save dialog, which sits at the modal panel level, since the recent
    /// locations list and the clipboard history are used over exactly those.
    /// `.floating` is below it, and the panel opened behind the dialog.
    static let sameKeysPanel = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
}
