import Carbon.HIToolbox

// What a key is called on a keycap. Kept out of the UI so it can be tested
// without a running app, and so both the Windows and the Mac spelling of a
// combination come from one place.

extension KeyCode {
    /// The text printed on this key's cap, such as "C", "Home" or "←".
    ///
    /// Unknown codes fall back to their number, so a rule made by hand is
    /// still recognisable instead of showing nothing.
    var label: String {
        if let named = Self.names[rawValue] { return named }
        if let character = Self.characters[rawValue] { return character }
        return "#\(rawValue)"
    }

    /// Keys with a name rather than a character, in the spelling macOS uses.
    private static let names: [UInt16: String] = [
        UInt16(kVK_Return): "Enter",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Escape): "Esc",
        // macOS labels the backwards-erasing key Delete and draws it ⌫;
        // Windows calls it Backspace. The symbol says it without picking.
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Command): "⌘",
        UInt16(kVK_Option): "⌥",
        UInt16(kVK_Control): "⌃",
        UInt16(kVK_Shift): "⇧",
        UInt16(kVK_CapsLock): "Caps Lock",
        UInt16(kVK_Function): "fn",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
    ]

    /// Keys that carry a character on a US layout. Key codes name positions,
    /// not characters, so another layout prints something else on the same
    /// key; the US spelling is what the shortcut lists everywhere use.
    private static let characters: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[", UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\", UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".", UInt16(kVK_ANSI_Slash): "/",
        UInt16(kVK_ANSI_Grave): "`",
    ]
}

/// How a combination is spelled: as the user's Windows keyboard says it, or
/// as macOS does.
enum KeyStyle: Sendable {
    /// Ctrl, Alt, Shift, Win — the trigger side of a mapping.
    case windows
    /// ⌃ ⌥ ⇧ ⌘ — the result side.
    case mac
}

extension Modifiers {
    /// One cap per modifier, in canonical order.
    func caps(_ style: KeyStyle) -> [String] {
        Self.capNames.filter { contains($0.modifier) }.map {
            switch style {
            case .windows: $0.windows
            case .mac: $0.mac
            }
        }
    }

    private static let capNames: [(modifier: Modifiers, windows: String, mac: String)] = [
        (.control, "Ctrl", "⌃"),
        (.option, "Alt", "⌥"),
        (.shift, "Shift", "⇧"),
        // A PC keyboard's Win key arrives as command, and that is how the
        // Windows side of a mapping is written.
        (.command, "Win", "⌘"),
        (.function, "fn", "fn"),
    ]
}

extension KeyCombo {
    /// Every cap of the combination, modifiers first.
    func caps(_ style: KeyStyle) -> [String] {
        modifiers.caps(style) + [key.label]
    }
}
