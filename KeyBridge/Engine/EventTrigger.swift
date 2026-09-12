import Carbon.HIToolbox
import CoreGraphics

extension Trigger {
    /// The trigger an incoming event sets off, or nil for events no rule
    /// reacts to: key and button releases, modifier changes, zero scrolls.
    init?(event: CGEvent, type: CGEventType) {
        let modifiers = Modifiers(flags: event.flags)
        switch type {
        case .keyDown:
            let key = KeyCode(rawValue: UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
            var keyModifiers = modifiers
            if key.carriesImplicitFunctionFlag {
                keyModifiers.remove(.function)
            }
            self = .key(combo: KeyCombo(keyModifiers, key))

        case .otherMouseDown:
            // CGEvent counts buttons from 0; users and rules count from 1.
            let number = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            self = .mouseButton(number: number, modifiers: modifiers)

        case .scrollWheel:
            let vertical = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let horizontal = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let direction: ScrollDirection
            if vertical == 0 && horizontal == 0 {
                return nil
            } else if abs(vertical) >= abs(horizontal) {
                direction = vertical > 0 ? .up : .down
            } else {
                direction = horizontal > 0 ? .left : .right
            }
            self = .scroll(direction: direction, modifiers: modifiers)

        default:
            return nil
        }
    }
}

extension Modifiers {
    /// The modifiers held in `flags`. Caps Lock and the numeric-keypad flag
    /// are not modifiers a rule can ask for, so they are dropped.
    init(flags: CGEventFlags) {
        self = []
        if flags.contains(.maskControl) { insert(.control) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskCommand) { insert(.command) }
        if flags.contains(.maskSecondaryFn) { insert(.function) }
    }
}

extension KeyCode {
    /// macOS sets the fn flag on every press of these keys, whether or not fn
    /// is held, and a MacBook produces some of them only through fn (fn+← is
    /// Home). The flag says nothing about the user's intent, so matching
    /// ignores it; a rule cannot require fn together with one of these keys.
    var carriesImplicitFunctionFlag: Bool {
        Self.implicitFunctionKeys.contains(rawValue)
    }

    private static let implicitFunctionKeys: Set<UInt16> = Set([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_Help,
    ].map { UInt16($0) })
}
