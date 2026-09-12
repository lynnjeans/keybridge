import CoreGraphics

/// Marks and recognizes the events KeyBridge synthesizes.
///
/// A remapped key is posted back into the event stream, where it flows through
/// KeyBridge's own tap again. Without a way to recognize it, a rule could
/// rewrite its own output, and two rules that map into each other would loop
/// forever. Every event KeyBridge posts goes through ``post(_:)``, which stamps
/// it, and the tap passes stamped events through untouched.
enum SyntheticEvent {
    /// Stamped into `eventSourceUserData`. The value only has to be
    /// distinctive; it spells "KEYB" in ASCII.
    static let marker: Int64 = 0x4B45_5942

    static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    /// Stamps `event` as KeyBridge's own and posts it.
    static func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cgSessionEventTap)
    }
}
