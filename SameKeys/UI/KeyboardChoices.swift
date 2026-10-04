import Foundation

/// The keyboards a per-keyboard choice is offered for (KB-076): those
/// connected, then those with settings of their own that are not, so an
/// override can still be seen and removed. Shown only from two keyboards on;
/// with one, the card's own choice is all there is.
struct KeyboardChoices {
    struct Entry: Identifiable {
        let keyboard: Keyboard
        let isConnected: Bool
        var id: Keyboard.ID { keyboard.id }
    }

    let entries: [Entry]

    init(connected: [Keyboard], withSettings: [KeyboardSettings]) {
        var entries = connected.map { Entry(keyboard: $0, isConnected: true) }
        for settings in withSettings where !entries.contains(where: { $0.id == settings.id }) {
            entries.append(Entry(keyboard: settings.keyboard, isConnected: false))
        }
        self.entries = entries
    }

    var isShown: Bool { entries.count >= 2 }
}

extension Keyboard {

    /// The name to show: the Mac's own keyboard calls itself "Apple Internal
    /// Keyboard / Trackpad", which says less than "Built-in Keyboard".
    var displayName: String {
        if isBuiltIn { return String(localized: "Built-in Keyboard") }
        return name.isEmpty ? String(format: "%04x:%04x", vendorID, productID) : name
    }
}
