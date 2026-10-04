import Carbon.HIToolbox
import Testing

@Suite struct KeyCodeLabelTests {
    @Test func lettersAndDigitsShowTheirCharacter() {
        #expect(KeyCode.c.label == "C")
        #expect(KeyCode.z.label == "Z")
        #expect(KeyCode.three.label == "3")
        #expect(KeyCode.equal.label == "=")
        #expect(KeyCode.leftBracket.label == "[")
    }

    @Test func namedKeysUseTheirNameOrSymbol() {
        #expect(KeyCode.home.label == "Home")
        #expect(KeyCode.end.label == "End")
        #expect(KeyCode.tab.label == "Tab")
        #expect(KeyCode.returnKey.label == "Enter")
        #expect(KeyCode.escape.label == "Esc")
        #expect(KeyCode.f2.label == "F2")
    }

    @Test func arrowsAndDeletionUseSymbols() {
        #expect(KeyCode.leftArrow.label == "←")
        #expect(KeyCode.downArrow.label == "↓")
        #expect(KeyCode.delete.label == "⌫", "Backspace on a PC keyboard")
        #expect(KeyCode.forwardDelete.label == "⌦")
    }

    @Test func anUnknownKeyShowsItsCode() {
        #expect(KeyCode(rawValue: 250).label == "#250")
    }

    /// Every key a built-in rule uses must be readable; a missing entry would
    /// show as a raw number in the Shortcuts list.
    @Test func everyBuiltInRuleKeyHasALabel() {
        var labels: [String] = []
        for rule in BuiltInRules.all {
            if case .key(let combo) = rule.trigger { labels.append(combo.key.label) }
            if case .key(let combo) = rule.action { labels.append(combo.key.label) }
        }
        let unnamed = labels.filter { $0.hasPrefix("#") }
        #expect(unnamed.isEmpty, "Unnamed keys: \(unnamed)")
    }

    @Test func modifiersAreSpelledForEachSide() {
        let combo = KeyCombo([.control, .shift], .c)
        #expect(combo.caps(.windows) == ["Ctrl", "Shift", "C"])
        #expect(KeyCombo([.command, .option], .v).caps(.mac) == ["⌥", "⌘", "V"])
    }

    @Test func theWindowsKeyIsNamedWinOnTheTriggerSide() {
        let combo = KeyCombo([.command], .e)
        #expect(combo.caps(.windows) == ["Win", "E"])
        #expect(combo.caps(.mac) == ["⌘", "E"])
    }

    @Test func capsFollowTheCanonicalOrder() {
        let all = KeyCombo([.function, .command, .shift, .option, .control], .a)
        #expect(all.caps(.mac) == ["⌃", "⌥", "⇧", "⌘", "fn", "A"])
    }

    /// Microsoft's order on the Windows side, fn where Ctrl goes (KB-232).
    @Test func theWindowsSideIsWinCtrlAltShift() {
        #expect(KeyCombo([.function, .shift], .g).caps(.windows) == ["fn", "Shift", "G"])
        #expect(KeyCombo([.control, .shift], .g).caps(.windows) == ["Ctrl", "Shift", "G"])
        #expect(KeyCombo([.shift, .command], .s).caps(.windows) == ["Win", "Shift", "S"])
        #expect(KeyCombo([.control, .option], .forwardDelete).caps(.windows) == ["Ctrl", "Alt", "⌦"])
        #expect(KeyCombo([.function, .command, .shift, .option, .control], .a).caps(.windows)
                == ["Win", "Ctrl", "fn", "Alt", "Shift", "A"])
        // Win is ⌥ and Alt is ⌘ by position; the order follows the names.
        #expect(KeyCombo([.shift, .option], .s).caps(.windowsByPosition) == ["Win", "Shift", "S"])
        #expect(KeyCombo([.control, .command], .forwardDelete).caps(.windowsByPosition) == ["Ctrl", "Alt", "⌦"])
        #expect(KeyCombo([.shift, .command], .s).caps(.mac) == ["⇧", "⌘", "S"], "The Mac side is unchanged")
    }
}
