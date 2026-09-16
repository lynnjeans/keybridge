import AppKit

extension KeyCombo {
    /// The combination a key press recorded in KeyBridge's own window stands
    /// for, read the same way the engine reads presses from the event tap.
    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        let key = KeyCode(rawValue: keyCode)
        var modifiers = Modifiers(modifierFlags: modifierFlags)
        // As in `Trigger(event:type:)`: arrows, F-keys and the like report fn
        // whether or not it is held, and a rule cannot ask for it with them.
        if key.carriesImplicitFunctionFlag {
            modifiers.remove(.function)
        }
        self.init(modifiers, key)
    }
}

extension Modifiers {
    init(modifierFlags flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.function) { insert(.function) }
    }
}
