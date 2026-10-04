import SwiftUI

/// Opening the clipboard history as a rule's result, in lists (KB-245).
struct ClipboardHistoryLabel: View {
    var body: some View {
        Label("Clipboard history", systemImage: "list.clipboard")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// What the result does, under the editor's choice of result: there is
/// nothing more to choose.
struct ClipboardHistoryNote: View {
    var body: some View {
        Text("Shows or hides the clipboard history, as its own shortcut does. Does nothing while the history is off.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
