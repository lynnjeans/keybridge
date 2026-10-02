import Foundation
import Testing

@Suite struct KeyboardListTests {
    /// The three devices an `IOHIDManager` matching keyboards found on the
    /// user's Mac (2026-10-02), as their registry properties.
    static var builtInDevice: [String: Any] { [
        "Product": "Apple Internal Keyboard / Trackpad", "Built-In": 1, "PrimaryUsagePage": 1, "PrimaryUsage": 6,
    ] }
    static var externalDevice: [String: Any] { [
        "Product": "RK-KB5.0 ", "VendorID": 14, "ProductID": 13330, "PrimaryUsagePage": 1, "PrimaryUsage": 6,
    ] }
    static var mouseDevice: [String: Any] { [
        "Product": "ProClick", "VendorID": 5426, "ProductID": 118, "PrimaryUsagePage": 1, "PrimaryUsage": 2,
    ] }

    @Test func aDeviceIsTheKeyboardItsEventsName() throws {
        // What KeyboardSource read from the event services beneath them.
        let builtInService: [String: Any] = ["Product": "Apple Internal Keyboard / Trackpad", "VendorID": 0, "ProductID": 0, "Built-In": true]
        let externalService: [String: Any] = ["Product": "RK-KB5.0 ", "VendorID": 14, "ProductID": 13330]

        let builtIn = try #require(KeyboardList.keyboard(fromDevice: Self.builtInDevice))
        let external = try #require(KeyboardList.keyboard(fromDevice: Self.externalDevice))
        #expect(builtIn == Keyboard(properties: builtInService))
        #expect(external == Keyboard(properties: externalService))
        #expect(builtIn.id == Keyboard.ID(vendorID: 0, productID: 0, isBuiltIn: true))
        #expect(external.id == Keyboard.ID(vendorID: 0x000E, productID: 0x3412, isBuiltIn: false))
    }

    @Test func aMouseWithAKeyboardCollectionIsNoKeyboard() {
        #expect(KeyboardList.keyboard(fromDevice: Self.mouseDevice) == nil)
        #expect(KeyboardList.keyboard(fromDevice: ["Product": "Keypad", "PrimaryUsagePage": 1, "PrimaryUsage": 7]) != nil)
        #expect(KeyboardList.keyboard(fromDevice: ["Product": "Unknown"]) == nil)
    }

    @Test func listsEachModelOnceBuiltInFirst() throws {
        let builtIn = try #require(KeyboardList.keyboard(fromDevice: Self.builtInDevice))
        let external = try #require(KeyboardList.keyboard(fromDevice: Self.externalDevice))
        let another = Keyboard(vendorID: 0x05AC, productID: 0x029C, name: "Magic Keyboard", isBuiltIn: false)
        // Two of the same model, say a keyboard on two connections.
        let list = KeyboardList.list([external, another, builtIn, external])
        #expect(list == [builtIn, another, external])
    }

    @Test func describesAKeyboardForTheLog() {
        #expect(Keyboard(vendorID: 0x000E, productID: 0x3412, name: "RK-KB5.0", isBuiltIn: false).description == "RK-KB5.0 (0x000e/0x3412)")
        #expect(Keyboard(vendorID: 0, productID: 0, name: "Apple Internal Keyboard / Trackpad", isBuiltIn: true).description
            == "Apple Internal Keyboard / Trackpad (built-in)")
    }
}
