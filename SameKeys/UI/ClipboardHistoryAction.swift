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
