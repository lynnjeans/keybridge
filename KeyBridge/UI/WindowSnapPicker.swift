import SwiftUI

extension WindowSnap {
    var name: String {
        switch self {
        case .leftHalf: String(localized: "Left half of the screen")
        case .rightHalf: String(localized: "Right half of the screen")
        case .maximize: String(localized: "Fill the screen")
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .maximize: "rectangle.fill"
        }
    }
}

/// A window position as a rule's result, in lists.
struct WindowSnapLabel: View {
    let snap: WindowSnap

    var body: some View {
        Label(snap.name, systemImage: snap.symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// Chooses where a rule puts the frontmost window.
struct WindowSnapPicker: View {
    @Binding var selection: WindowSnap

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Window position", selection: $selection) {
                ForEach(WindowSnap.allCases, id: \.self) { snap in
                    Label(snap.name, systemImage: snap.symbol).tag(snap)
                }
            }
            .labelsHidden()
            .fixedSize()
            Text("Moves the window in front. Full-screen windows are left alone.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
