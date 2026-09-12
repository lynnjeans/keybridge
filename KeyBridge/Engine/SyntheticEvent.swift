import CoreGraphics

/// Creates, marks and recognizes the events KeyBridge synthesizes.
///
/// A remapped key is posted back into the event stream, where it flows through
/// KeyBridge's own tap again. Without a way to recognize it, a rule could
/// rewrite its own output, and two rules that map into each other would loop
/// forever. Every event KeyBridge creates is stamped, and the tap passes
/// stamped events through untouched.
enum SyntheticEvent {
    /// Stamped into `eventSourceUserData`. The value only has to be
    /// distinctive; it spells "KEYB" in ASCII.
    static let marker: Int64 = 0x4B45_5942

    static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    static func stamp(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    /// Stamps `event` as KeyBridge's own and posts it.
    static func post(_ event: CGEvent) {
        stamp(event)
        event.post(tap: .cgSessionEventTap)
    }

    /// A stamped key event for `combo`.
    ///
    /// The event carries exactly the combination's modifiers, whatever the user
    /// is physically holding: the Ctrl of Ctrl+C must not leak into the ⌘C
    /// that replaces it. When `original` is given, the new event takes over its
    /// timestamp, auto-repeat marker and keyboard type, so it reads as the same
    /// keystroke with a different meaning.
    @MainActor
    static func key(_ combo: KeyCombo, down: Bool, replacing original: CGEvent? = nil) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: combo.key.rawValue, keyDown: down) else {
            return nil
        }
        var flags = CGEventFlags(combo.modifiers)
        // Match what the hardware sends for these keys, which some apps rely on.
        if combo.key.carriesImplicitFunctionFlag { flags.insert(.maskSecondaryFn) }
        if combo.key.isArrow { flags.insert(.maskNumericPad) }
        event.flags = flags

        if let original {
            event.timestamp = original.timestamp
            for field in [CGEventField.keyboardEventAutorepeat, .keyboardEventKeyboardType] {
                event.setIntegerValueField(field, value: original.getIntegerValueField(field))
            }
        }
        stamp(event)
        return event
    }

    /// A private source keeps the characters macOS derives for a new event
    /// independent of the modifiers physically held, which a shared source
    /// would mix in.
    @MainActor private static let source = CGEventSource(stateID: .privateState)
}
