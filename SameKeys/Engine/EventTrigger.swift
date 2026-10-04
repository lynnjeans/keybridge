import AppKit
import Carbon.HIToolbox
import CoreGraphics

extension Trigger {
    /// The trigger an incoming event sets off, or nil for events no rule
    /// reacts to: key and button releases, modifier changes, zero scrolls.
    init?(event: CGEvent, type: CGEventType) {
        let modifiers = Modifiers(flags: event.flags)
        switch type {
        case .keyDown:
            let key = event.keyCode
            var keyModifiers = modifiers
            if key.carriesImplicitFunctionFlag {
                keyModifiers.remove(.function)
            }
            self = .key(combo: KeyCombo(keyModifiers, key))

        case .otherMouseDown:
            self = .mouseButton(number: event.mouseButtonNumber, modifiers: modifiers)

        case .scrollWheel:
            // Scroll rules are for mouse wheels. A trackpad's scrolling already
            // works the way users expect and must never trigger page zoom.
            guard event.scrollSource != .gesture, let direction = event.scrollDirection else { return nil }
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

extension CGEventFlags {
    init(_ modifiers: Modifiers) {
        self = []
        if modifiers.contains(.control) { insert(.maskControl) }
        if modifiers.contains(.option) { insert(.maskAlternate) }
        if modifiers.contains(.shift) { insert(.maskShift) }
        if modifiers.contains(.command) { insert(.maskCommand) }
        if modifiers.contains(.function) { insert(.maskSecondaryFn) }
    }
}

/// Where a scroll event came from, as far as the event itself can tell.
enum ScrollSource: String, CaseIterable, Sendable {
    /// A classic wheel that moves in notches, one line at a time.
    case notchedWheel
    /// A wheel that scrolls smoothly, such as a free-spinning or
    /// high-resolution wheel.
    case smoothWheel
    /// A touch gesture: a trackpad, or a Magic Mouse's touch surface.
    case gesture
}

extension CGEvent {
    /// Touch gestures report a scroll phase (began, changed, ended) and,
    /// after the fingers lift, a momentum phase; wheels report neither. Being
    /// continuous is not enough to tell them apart, since smooth wheels are
    /// continuous too.
    ///
    /// Smooth-scrolling utilities (Mos, SmoothScroll and the like) re-post
    /// wheel scrolling as synthetic gestures, which then counts as a gesture.
    var scrollSource: ScrollSource {
        let phase = getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = getIntegerValueField(.scrollWheelEventMomentumPhase)
        if phase != 0 || momentum != 0 { return .gesture }
        return getIntegerValueField(.scrollWheelEventIsContinuous) == 0 ? .notchedWheel : .smoothWheel
    }

    /// Which way the wheel physically turned, or nil for a scroll with no
    /// movement. `up` is the wheel rolled away from the user.
    ///
    /// With natural scrolling on, macOS reports deltas in the direction the
    /// content moves, which is the opposite; that is undone here, so a rule
    /// means the same gesture whatever the user's scrolling preference.
    var scrollDirection: ScrollDirection? {
        let vertical = getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let horizontal = getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        guard vertical != 0 || horizontal != 0 else { return nil }
        let inverted = NSEvent(cgEvent: self)?.isDirectionInvertedFromDevice ?? false
        let direction: ScrollDirection
        if abs(vertical) >= abs(horizontal) {
            direction = (vertical > 0) != inverted ? .up : .down
        } else {
            direction = (horizontal > 0) != inverted ? .left : .right
        }
        return direction
    }

    /// How far the scroll moved along its main axis, in lines.
    var scrollLines: Double {
        let vertical = getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let horizontal = getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        return max(abs(vertical), abs(horizontal))
    }

    var keyCode: KeyCode {
        KeyCode(rawValue: UInt16(getIntegerValueField(.keyboardEventKeycode)))
    }

    /// The mouse button, numbered the way users see it: CGEvent counts from 0,
    /// users and rules from 1, so the side buttons are 4 and 5.
    var mouseButtonNumber: Int {
        Int(getIntegerValueField(.mouseEventButtonNumber)) + 1
    }

    /// True for the repeated key-downs macOS generates while a key is held.
    var isAutorepeat: Bool {
        getIntegerValueField(.keyboardEventAutorepeat) != 0
    }
}

extension KeyCode {
    var isArrow: Bool {
        [.leftArrow, .rightArrow, .upArrow, .downArrow].contains(self)
    }

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
