import SwiftUI

extension FileDialogAction {
    var name: String {
        switch self {
        case .finderFolder: String(localized: "Finder's current folder")
        }
    }

    var symbol: String {
        switch self {
        case .finderFolder: "folder"
        }
    }
}

/// A file dialog action as a rule's result, in lists.
struct FileDialogActionLabel: View {
    let action: FileDialogAction

    var body: some View {
        Label(action.name, systemImage: action.symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// Chooses what a rule does in an open or save dialog.
struct FileDialogActionPicker: View {
    @Binding var selection: FileDialogAction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Dialog action", selection: $selection) {
                ForEach(FileDialogAction.allCases, id: \.self) { action in
                    Label(action.name, systemImage: action.symbol).tag(action)
                }
            }
            .labelsHidden()
            .fixedSize()
            Text("Only in an open or save dialog; anywhere else the shortcut does what it always did.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
