import SwiftUI

/// The Switch Input Source result (SK-277), as a rule's result is shown.
struct InputSourceLabel: View {
    var body: some View {
        Label("Switch input source", systemImage: "globe")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// What the result does, under the editor's choice of result: there is
/// nothing more to choose.
struct InputSourceNote: View {
    var body: some View {
        Text("Switches between ABC and the input method you used last, such as Pinyin, like Caps Lock does, without the input source switcher on screen.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
