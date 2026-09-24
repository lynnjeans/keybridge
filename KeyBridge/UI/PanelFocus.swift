import AppKit
import OSLog

extension NSWindow {
    /// Puts the insertion point in the window's first editable text field,
    /// with its text selected and scrolled to the end, for the floating
    /// panels (the path box and the clipboard history) that are typed into
    /// the moment they open.
    ///
    /// SwiftUI's `@FocusState` set from `onAppear` never reaches the field
    /// in a non-activating panel — the panel stays its own first responder —
    /// so AppKit is asked directly. An `NSTextField` becoming first responder
    /// selects its text, so a paste replaces what was there; a long text
    /// shows its end, which for a path is the folder the person is in.
    ///
    /// The hosting view builds the field only when it is laid out. Waiting a
    /// few run loop turns for that missed it now and then on the first
    /// opening after launch, so layout is forced, which builds it at once
    /// (8 of 8 cold launches); the search is retried every 20 ms for up to
    /// a second should that ever not be enough.
    @MainActor
    func focusFirstTextField(attempts: Int = 50) {
        contentView?.layoutSubtreeIfNeeded()
        guard let field = contentView.flatMap(Self.firstTextField(in:)) else {
            guard attempts > 1 else {
                Logger.window.error("no text field to focus in \(self.title, privacy: .public)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.focusFirstTextField(attempts: attempts - 1)
            }
            return
        }
        makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.scrollRangeToVisible(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }

    private static func firstTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = firstTextField(in: subview) { return field }
        }
        return nil
    }
}
