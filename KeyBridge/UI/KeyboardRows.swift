import SwiftUI

/// One keyboard's own row in a card (KB-076): its name, what it does with an
/// example, and the card's options as a segmented control showing what the
/// keyboard really uses — never "the same as" something else on the page,
/// which left the user to work out what that was.
struct KeyboardRow<Value: Hashable, Options: View>: View {
    let entry: KeyboardChoices.Entry
    /// One example of what the chosen value does on this keyboard.
    let example: Text
    @Binding var value: Value
    @ViewBuilder let options: Options

    var body: some View {
        AdaptiveRow(minFlexibleWidth: 160) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.keyboard.displayName)
                        .fontWeight(.medium)
                    if !entry.isConnected {
                        Text("Not connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                example
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker(entry.keyboard.displayName, selection: $value) { options }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
        }
    }
}
