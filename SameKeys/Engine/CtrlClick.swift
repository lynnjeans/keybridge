import CoreGraphics

/// A left click with the Windows Ctrl key held goes out as ⌘+click (KB-222):
/// it adds to a selection and opens a link in a new tab, as Ctrl+click does
/// on Windows.
///
/// The key is the one the Shortcuts page's Ctrl / fn choice names, so in fn
/// mode it is fn+click, which means nothing else on a Mac. With Ctrl it takes
/// over macOS's Ctrl+click for the shortcut menu, which is why the setting
/// is off until switched on. Only the flags of the button's own events
/// change; nothing is added or swallowed.
struct CtrlClick: Equatable, Sendable {
    let controlKey: ControlKey

    /// The flags a press goes out with, or nil to leave it as it is.
    func rewrite(_ flags: CGEventFlags) -> CGEventFlags? {
        let held: CGEventFlags
        switch controlKey {
        case .control: held = flags.intersection(.maskControl)
        case .function: held = flags.intersection(.maskSecondaryFn)
        case .both: held = flags.intersection([.maskControl, .maskSecondaryFn])
        }
        guard !held.isEmpty else { return nil }
        return flags.subtracting(held).union(.maskCommand)
    }

    /// The flags the release of a rewritten press goes out with: ⌘ still,
    /// even when the key was let go of first, so the app sees one ⌘+click.
    static func release(_ flags: CGEventFlags) -> CGEventFlags {
        flags.subtracting([.maskControl, .maskSecondaryFn]).union(.maskCommand)
    }
}
