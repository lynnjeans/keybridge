import Carbon.HIToolbox
import CoreGraphics

/// Recognises a modifier key pressed and released on its own, such as the Win
/// key tapped to open the Start menu (KB-224). A rule reacts to it through a
/// key trigger with no modifiers whose key is the modifier key itself:
/// `KeyCombo(.command)` is Win alone.
///
/// A press counts only if no other modifier was held, and it is cancelled by
/// anything else in between: another key, a click, a scroll, a second
/// modifier. So is a press held longer than `timeout`, since letting go of ⌘
/// after thinking better of a shortcut is not a tap. Left and right keys are
/// the same key here, as they are for `Modifiers`.
///
/// The modifier's own events always go through unchanged: by the time a
/// release shows the press was alone, the press has long reached the app.
struct ModifierTap {
    /// Karabiner-Elements' default for `to_if_alone`, which is what people
    /// who configured this before will be used to.
    static let timeout: UInt64 = 1_000_000_000

    private var pending: (key: KeyCode, start: UInt64)?

    /// Takes a modifier change and returns the key that was tapped, if this
    /// change completes a tap.
    ///
    /// - Parameters:
    ///   - key: the key code of the `flagsChanged` event.
    ///   - flags: its flags, including the device-dependent bits that say
    ///     which side's key is down.
    ///   - now: a time in nanoseconds.
    mutating func flagsChanged(key: KeyCode, flags: CGEventFlags, now: UInt64) -> KeyCode? {
        guard let side = Self.sides[key.rawValue] else {
            // Caps Lock and the like.
            pending = nil
            return nil
        }
        let held = Modifiers(flags: flags)
        if Self.isDown(side, in: flags) {
            pending = held == side.modifier ? (side.key, now) : nil
            return nil
        }
        defer { pending = nil }
        guard let pending, pending.key == side.key, held.isEmpty,
              now >= pending.start, now - pending.start <= Self.timeout else { return nil }
        return side.key
    }

    /// Something other than a modifier happened; a modifier held meanwhile
    /// was part of a shortcut, not a tap.
    mutating func interrupt() {
        pending = nil
    }

    private struct Side {
        /// The left key's code, which stands for both.
        let key: KeyCode
        let modifier: Modifiers
        /// The device-dependent flag for this physical key; fn has none, and
        /// its own flag is used instead.
        let deviceMask: UInt64
    }

    /// Whether the key an event is about is down after it. The device bits
    /// tell the two ⌘ keys apart; an event made by software may carry none,
    /// and then the plain modifier flag has to do.
    private static func isDown(_ side: Side, in flags: CGEventFlags) -> Bool {
        if flags.rawValue & deviceMasks != 0 || side.modifier == .function {
            return flags.rawValue & side.deviceMask != 0
        }
        return Modifiers(flags: flags).contains(side.modifier)
    }

    // NX_DEVICE…KEYMASK in IOKit's IOLLEvent.h.
    private static let deviceMasks: UInt64 = 0x207F

    private static let sides: [UInt16: Side] = {
        func side(_ code: Int, _ left: Int, _ modifier: Modifiers, _ mask: UInt64) -> (UInt16, Side) {
            (UInt16(code), Side(key: KeyCode(rawValue: UInt16(left)), modifier: modifier, deviceMask: mask))
        }
        return Dictionary(uniqueKeysWithValues: [
            side(kVK_Control, kVK_Control, .control, 0x0001),
            side(kVK_RightControl, kVK_Control, .control, 0x2000),
            side(kVK_Shift, kVK_Shift, .shift, 0x0002),
            side(kVK_RightShift, kVK_Shift, .shift, 0x0004),
            side(kVK_Command, kVK_Command, .command, 0x0008),
            side(kVK_RightCommand, kVK_Command, .command, 0x0010),
            side(kVK_Option, kVK_Option, .option, 0x0020),
            side(kVK_RightOption, kVK_Option, .option, 0x0040),
            side(kVK_Function, kVK_Function, .function, CGEventFlags.maskSecondaryFn.rawValue),
        ])
    }()
}
