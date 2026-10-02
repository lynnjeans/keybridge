import CoreGraphics
import Foundation
import IOKit

/// A keyboard, as far as a setting can be kept for it (KB-021).
///
/// Two keyboards of the same model count as one: they report the same vendor
/// and product, and nothing else about a keyboard outlasts its being
/// unplugged.
struct Keyboard: Hashable, Codable, Sendable {
    let vendorID: Int
    let productID: Int
    /// What the keyboard calls itself, for showing.
    let name: String
    /// The Mac's own keyboard.
    let isBuiltIn: Bool

    /// Reads a keyboard from its HID event service's registry properties.
    init(properties: [String: Any]) {
        vendorID = properties[Keyboard.vendorKey] as? Int ?? 0
        productID = properties[Keyboard.productIDKey] as? Int ?? 0
        // Some keyboards pad their name: "RK-KB5.0 ".
        name = (properties[Keyboard.nameKey] as? String ?? "").trimmingCharacters(in: .whitespaces)
        // A boolean on the event service, a number on some devices.
        isBuiltIn = (properties[Keyboard.builtInKey] as? NSNumber)?.boolValue ?? false
    }

    init(vendorID: Int, productID: Int, name: String, isBuiltIn: Bool) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.isBuiltIn = isBuiltIn
    }

    static let vendorKey = "VendorID"
    static let productIDKey = "ProductID"
    static let nameKey = "Product"
    static let builtInKey = "Built-In"
    /// Everything a keyboard is read from, on an event service or a device.
    static let registryKeys = [vendorKey, productIDKey, nameKey, builtInKey]

    /// What a setting is kept under (KB-243): the model, not the name, which
    /// a keyboard may report padded or a user may change. The built-in
    /// keyboard reports no vendor or product at all; being built in is what
    /// tells it apart.
    struct ID: Hashable, Codable, Sendable {
        let vendorID: Int
        let productID: Int
        let isBuiltIn: Bool
    }

    var id: ID { ID(vendorID: vendorID, productID: productID, isBuiltIn: isBuiltIn) }
}

extension Keyboard: CustomStringConvertible {
    /// For the log and the diagnostic report: "RK-KB5.0 (0x000e/0x3412)",
    /// "Apple Internal Keyboard / Trackpad (built-in)".
    var description: String {
        isBuiltIn ? "\(name) (built-in)" : String(format: "%@ (0x%04x/0x%04x)", name, vendorID, productID)
    }
}

/// Tells which keyboard a key event came from (KB-021).
///
/// Nothing documented in an event says so. Integer field 87, which
/// `CGEventField` does not name, holds the registry entry ID of the HID event
/// service that sent the event, and that entry says which keyboard it serves.
/// Measured on macOS 26.6 against an `IOHIDManager` that knows the device of
/// every key value: 226 of 226 events, on the built-in keyboard and a
/// Bluetooth one (`docs/testing-notes.md`, Keyboards). An event posted by
/// software has 0 there.
///
/// Since this rests on undocumented behaviour, nothing is taken on trust: the
/// ID has to be that of a HID entry in the registry, or there is no keyboard,
/// and whatever is kept per keyboard falls back to what applies to all.
@MainActor
final class KeyboardSource {
    /// Registry lookups that found nothing, after which a run with none that
    /// found a keyboard stops looking: the field holds something else on this
    /// system, and a lookup for every key press would be wasted in the event
    /// tap's callback.
    static let missLimit = 16

    private var known: [UInt64: Keyboard?] = [:]
    private var hits = 0
    private var misses = 0
    private let lookUp: (UInt64) -> Keyboard?

    /// Whether lookups have stopped for this run (see `missLimit`).
    var hasGivenUp: Bool { hits == 0 && misses >= Self.missLimit }

    init(lookUp: @escaping (UInt64) -> Keyboard? = KeyboardSource.keyboard(ofRegistryEntry:)) {
        self.lookUp = lookUp
    }

    /// The keyboard `event` came from; nil for an event software posted, or
    /// when the system does not say.
    func keyboard(of event: CGEvent) -> Keyboard? {
        keyboard(ofSender: event.senderID)
    }

    /// The keyboard served by the registry entry with this ID. The registry
    /// is read once for each ID: an ID belongs to one entry until the Mac
    /// restarts, and a keyboard that reconnects comes back with a new one.
    func keyboard(ofSender id: UInt64) -> Keyboard? {
        guard id != 0 else { return nil }
        if let keyboard = known[id] { return keyboard }
        guard !hasGivenUp else { return nil }
        // Every reconnection adds an ID; starting over costs one lookup each.
        if known.count >= 64 { known.removeAll() }
        let keyboard = lookUp(id)
        known.updateValue(keyboard, forKey: id)
        if keyboard == nil { misses += 1 } else { hits += 1 }
        return keyboard
    }

    /// Reads the keyboard from the registry; nil unless the entry is a HID
    /// event service or device.
    nonisolated static func keyboard(ofRegistryEntry id: UInt64) -> Keyboard? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard IOObjectConformsTo(entry, "IOHIDEventService") != 0 || IOObjectConformsTo(entry, "IOHIDDevice") != 0 else {
            return nil
        }
        var properties: [String: Any] = [:]
        for key in Keyboard.registryKeys {
            properties[key] = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        return Keyboard(properties: properties)
    }
}

extension CGEvent {
    /// The registry entry ID of the HID event service that sent this event;
    /// 0 for an event software posted. Undocumented: see `KeyboardSource`.
    var senderID: UInt64 {
        guard let field = CGEventField(rawValue: 87) else { return 0 }
        return UInt64(bitPattern: getIntegerValueField(field))
    }
}
