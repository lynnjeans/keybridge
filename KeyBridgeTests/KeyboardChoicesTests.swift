import Foundation
import Testing

@MainActor
@Suite struct KeyboardChoicesTests {
    static let builtIn = Keyboard(vendorID: 0, productID: 0, name: "Apple Internal Keyboard / Trackpad", isBuiltIn: true)
    static let external = Keyboard(vendorID: 0x000E, productID: 0x3412, name: "RK-KB5.0", isBuiltIn: false)

    @Test func oneKeyboardShowsNoRows() {
        #expect(!KeyboardChoices(connected: [Self.builtIn], withSettings: []).isShown)
        #expect(!KeyboardChoices(connected: [], withSettings: []).isShown)
    }

    @Test func aSecondKeyboardShowsARowForEach() {
        let choices = KeyboardChoices(connected: [Self.builtIn, Self.external], withSettings: [])
        #expect(choices.isShown)
        #expect(choices.entries.map(\.keyboard) == [Self.builtIn, Self.external])
        #expect(choices.entries.allSatisfy { $0.isConnected })
    }

    @Test func aKeyboardWithSettingsStaysListedUnplugged() {
        let settings = KeyboardSettings(keyboard: Self.external, controlKey: .control)
        let choices = KeyboardChoices(connected: [Self.builtIn], withSettings: [settings])
        #expect(choices.isShown, "Its setting can still be seen and removed")
        #expect(choices.entries.map(\.isConnected) == [true, false])

        let plugged = KeyboardChoices(connected: [Self.builtIn, Self.external], withSettings: [settings])
        #expect(plugged.entries.count == 2, "Connected and with settings is one row")
    }

    @Test func appleKeyboardsHaveMacKeys() {
        #expect(Self.builtIn.hasMacKeys)
        #expect(Keyboard(vendorID: 0x05AC, productID: 0x029C, name: "Magic Keyboard", isBuiltIn: false).hasMacKeys)
        #expect(Keyboard(vendorID: 0x004C, productID: 0x0267, name: "Magic Keyboard", isBuiltIn: false).hasMacKeys)
        #expect(!Self.external.hasMacKeys, "RK-KB5.0 is printed Win and Alt")
    }

    @Test func theBuiltInKeyboardIsCalledThat() {
        #expect(Self.builtIn.displayName != Self.builtIn.name)
        #expect(Self.external.displayName == "RK-KB5.0")
    }

    @Test func theOverviewCoversEveryKeyboard() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "KeyBridgeTests-\(UUID().uuidString)")
        let rules = RulesController(store: ConfigurationStore(fileURL: folder.appending(path: "config.json")))
        rules.setControlKey(.function)
        #expect(rules.controlKeysInUse == [.function])
        rules.setControlKey(.control, for: Self.external)
        rules.setModifierLayout(.macPosition)
        rules.setModifierLayout(.pcKeyboard, for: Self.external)
        #expect(rules.controlKeysInUse == [.function, .control])
        #expect(rules.modifierLayoutsInUse == [.macPosition, .pcKeyboard])
        rules.setControlKey(nil, for: Self.external)
        rules.setModifierLayout(nil, for: Self.external)
        #expect(rules.keyboardSettings.isEmpty)
        #expect(rules.controlKeysInUse == [.function])
    }

    @Test func choosingWhatEveryoneUsesKeepsNothingOfItsOwn() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "KeyBridgeTests-\(UUID().uuidString)")
        let rules = RulesController(store: ConfigurationStore(fileURL: folder.appending(path: "config.json")))
        rules.setControlKey(.function)
        rules.chooseControlKey(.control, for: Self.external)
        #expect(rules.configuration.controlKey(for: Self.external.id) == .control)
        #expect(rules.keyboardSettings.count == 1)
        // The built-in keyboard's row set to what it already uses.
        rules.chooseControlKey(.function, for: Self.builtIn)
        #expect(rules.keyboardSettings.count == 1, "Nothing written for a keyboard that does not differ")
        rules.chooseModifierLayout(.pcKeyboard, for: Self.external)
        rules.chooseModifierLayout(.macPosition, for: Self.external)
        #expect(rules.configuration.settings(for: Self.external.id)?.modifierLayout == .macPosition)
        rules.chooseModifierLayout(.pcKeyboard, for: Self.external)
        #expect(rules.configuration.settings(for: Self.external.id)?.modifierLayout == nil, "Back to the general one")
        // Back to what everyone uses: the keyboard follows the general choice again.
        rules.chooseControlKey(.function, for: Self.external)
        #expect(rules.keyboardSettings.isEmpty)
    }
}
