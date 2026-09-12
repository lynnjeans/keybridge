import Carbon.HIToolbox

/// A physical key, identified by its macOS virtual key code.
///
/// Key codes name positions on the keyboard, not the characters printed on
/// them, so a rule keeps working when the user switches input source.
struct KeyCode: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    private init(_ carbon: Int) {
        self.rawValue = UInt16(carbon)
    }
}

// Named keys used by the built-in presets. Add more as rules need them; any
// other key can still be expressed through `init(rawValue:)`.
extension KeyCode {
    static let a = KeyCode(kVK_ANSI_A)
    static let c = KeyCode(kVK_ANSI_C)
    static let d = KeyCode(kVK_ANSI_D)
    static let e = KeyCode(kVK_ANSI_E)
    static let f = KeyCode(kVK_ANSI_F)
    static let l = KeyCode(kVK_ANSI_L)
    static let n = KeyCode(kVK_ANSI_N)
    static let o = KeyCode(kVK_ANSI_O)
    static let p = KeyCode(kVK_ANSI_P)
    static let q = KeyCode(kVK_ANSI_Q)
    static let r = KeyCode(kVK_ANSI_R)
    static let s = KeyCode(kVK_ANSI_S)
    static let t = KeyCode(kVK_ANSI_T)
    static let v = KeyCode(kVK_ANSI_V)
    static let w = KeyCode(kVK_ANSI_W)
    static let x = KeyCode(kVK_ANSI_X)
    static let y = KeyCode(kVK_ANSI_Y)
    static let z = KeyCode(kVK_ANSI_Z)
    static let three = KeyCode(kVK_ANSI_3)
    static let four = KeyCode(kVK_ANSI_4)
    static let equal = KeyCode(kVK_ANSI_Equal)
    static let minus = KeyCode(kVK_ANSI_Minus)
    static let period = KeyCode(kVK_ANSI_Period)
    static let leftBracket = KeyCode(kVK_ANSI_LeftBracket)
    static let rightBracket = KeyCode(kVK_ANSI_RightBracket)

    static let returnKey = KeyCode(kVK_Return)
    static let tab = KeyCode(kVK_Tab)
    static let space = KeyCode(kVK_Space)
    static let escape = KeyCode(kVK_Escape)
    /// The key macOS labels Delete, which erases backwards (Windows Backspace).
    static let delete = KeyCode(kVK_Delete)
    /// Erases forwards (Windows Delete).
    static let forwardDelete = KeyCode(kVK_ForwardDelete)
    static let home = KeyCode(kVK_Home)
    static let end = KeyCode(kVK_End)
    static let leftArrow = KeyCode(kVK_LeftArrow)
    static let rightArrow = KeyCode(kVK_RightArrow)
    static let upArrow = KeyCode(kVK_UpArrow)
    static let downArrow = KeyCode(kVK_DownArrow)
    static let command = KeyCode(kVK_Command)

    static let f1 = KeyCode(kVK_F1)
    static let f2 = KeyCode(kVK_F2)
    static let f4 = KeyCode(kVK_F4)
    static let f11 = KeyCode(kVK_F11)
    static let f12 = KeyCode(kVK_F12)
    /// PC keyboards send Print Screen as F13 on macOS.
    static let f13 = KeyCode(kVK_F13)
}

/// The modifier keys a combination is made of. Left and right variants are
/// not distinguished.
///
/// A Windows keyboard's Win key arrives as `command` and its Alt key as
/// `option`, so a Windows shortcut is written in those terms: Win+L is
/// `[.command] + L`, Alt+Tab is `[.option] + Tab`.
struct Modifiers: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    static let control = Modifiers(rawValue: 1 << 0)
    static let option = Modifiers(rawValue: 1 << 1)
    static let shift = Modifiers(rawValue: 1 << 2)
    static let command = Modifiers(rawValue: 1 << 3)
    static let function = Modifiers(rawValue: 1 << 4)

    /// Stable names used in the configuration file, in canonical order.
    fileprivate static let names: [(Modifiers, String)] = [
        (.control, "control"),
        (.option, "option"),
        (.shift, "shift"),
        (.command, "command"),
        (.function, "fn"),
    ]
}

// Encoded as a list of names rather than a bit mask, so a configuration file
// stays readable and does not depend on the bit layout above.
extension Modifiers: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        var modifiers: Modifiers = []
        for name in try container.decode([String].self) {
            guard let match = Self.names.first(where: { $0.1 == name }) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unknown modifier \"\(name)\""
                )
            }
            modifiers.insert(match.0)
        }
        self = modifiers
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.names.filter { contains($0.0) }.map(\.1))
    }
}

/// A key pressed together with a set of modifiers, such as ⌃C.
struct KeyCombo: Codable, Hashable, Sendable {
    var modifiers: Modifiers
    var key: KeyCode

    init(_ modifiers: Modifiers, _ key: KeyCode) {
        self.modifiers = modifiers
        self.key = key
    }

    /// A key on its own, such as Home.
    init(_ key: KeyCode) {
        self.init([], key)
    }
}
