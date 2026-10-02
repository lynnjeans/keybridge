import SwiftUI

/// A row per keyboard under a card's choice: "Same as above", or one of the
/// card's options for that keyboard alone.
struct KeyboardRows<Value: Hashable>: View {
    let choices: KeyboardChoices
    /// The card's options, as its segmented control shows them.
    let options: [(value: Value, label: Text)]
    let value: (Keyboard) -> Value?
    let setValue: (Value?, Keyboard) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By keyboard")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(choices.entries) { entry in
                AdaptiveRow(minFlexibleWidth: 160) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.keyboard.displayName)
                        if !entry.isConnected {
                            Text("Not connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker(entry.keyboard.displayName, selection: Binding(
                        get: { value(entry.keyboard) },
                        set: { setValue($0, entry.keyboard) }
                    )) {
                        Text("Same as above").tag(Value?.none)
                        Divider()
                        ForEach(options.indices, id: \.self) { index in
                            options[index].label.tag(Optional(options[index].value))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}
