import SwiftUI

/// One keyboard's own row in a card (KB-076): its name, what it does with an
/// example, and the card's options as a segmented control showing what the
/// keyboard really uses — never "the same as" something else on the page,
/// which left the user to work out what that was.
struct KeyboardRow<Trailing: View>: View {
    let entry: KeyboardChoices.Entry
    /// One example of what the keyboard does with what is chosen.
    let example: Text
    /// The card's control for this keyboard, or a value with no choice.
    @ViewBuilder let trailing: Trailing

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
            trailing
        }
    }
}

extension KeyboardRow {
    /// A row whose control is the card's options as a segmented control,
    /// set to what the keyboard really uses.
    init<Value: Hashable, Options: View>(
        entry: KeyboardChoices.Entry, example: Text, value: Binding<Value>,
        @ViewBuilder options: () -> Options
    ) where Trailing == AnyView {
        self.init(entry: entry, example: example) {
            AnyView(Picker(entry.keyboard.displayName, selection: value) { options() }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize())
        }
    }
}
