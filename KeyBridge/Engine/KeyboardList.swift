import Foundation
import IOKit.hid
import Observation
import OSLog

/// The keyboards connected right now (KB-020), for settings kept per
/// keyboard (KB-243) and the rows that show them (KB-076).
///
/// An `IOHIDManager` reports keyboards as they connect and disconnect. It is
/// never opened: being told about devices needs no permission, and nothing
/// here reads a key. A keyboard is built from the device's registry
/// properties, the same ones `KeyboardSource` reads from the event service
/// beneath it, so both name a keyboard alike (measured on macOS 26.6: the
/// built-in keyboard has no vendor or product in either, and an external one
/// has the same in both).
@MainActor
@Observable
final class KeyboardList {
    /// Built-in first, then by name; one entry per model.
    private(set) var connected: [Keyboard] = []

    /// Told the list each time it changes, for the engine.
    @ObservationIgnored var onChange: (([Keyboard]) -> Void)?

    @ObservationIgnored private var devices: [IOHIDDevice: Keyboard] = [:]
    @ObservationIgnored private var manager: IOHIDManager?

    /// Starts listening. The keyboards already connected are reported at
    /// once, through the same callback as later ones.
    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad],
        ] as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let list = Unmanaged<KeyboardList>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { list.add(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let list = Unmanaged<KeyboardList>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { list.remove(device) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.manager = manager
    }

    private func add(_ device: IOHIDDevice) {
        var properties: [String: Any] = [:]
        for key in Self.propertyKeys {
            properties[key] = IOHIDDeviceGetProperty(device, key as CFString)
        }
        guard let keyboard = Self.keyboard(fromDevice: properties) else { return }
        devices[device] = keyboard
        scheduleUpdate()
    }

    private func remove(_ device: IOHIDDevice) {
        guard devices.removeValue(forKey: device) != nil else { return }
        scheduleUpdate()
    }

    @ObservationIgnored private var isUpdateScheduled = false

    /// The keyboards already connected arrive one callback each, all in the
    /// same turn of the run loop; the list changes once for all of them.
    private func scheduleUpdate() {
        guard !isUpdateScheduled else { return }
        isUpdateScheduled = true
        DispatchQueue.main.async { [self] in
            isUpdateScheduled = false
            update()
        }
    }

    private func update() {
        let list = Self.list(Array(devices.values))
        guard list != connected else { return }
        connected = list
        onChange?(list)
        Logger.keyboards.notice("Keyboards: \(list.map(\.description).joined(separator: ", "), privacy: .public)")
    }

    nonisolated static let propertyKeys = Keyboard.registryKeys + [kIOHIDPrimaryUsagePageKey, kIOHIDPrimaryUsageKey]

    /// The keyboard a device is, or nil for one that is something else first.
    /// A mouse with programmable buttons often has a keyboard collection too
    /// (the Razer ProClick does), and would otherwise be listed.
    nonisolated static func keyboard(fromDevice properties: [String: Any]) -> Keyboard? {
        let page = properties[kIOHIDPrimaryUsagePageKey] as? Int
        let usage = properties[kIOHIDPrimaryUsageKey] as? Int
        guard page == kHIDPage_GenericDesktop,
              usage == kHIDUsage_GD_Keyboard || usage == kHIDUsage_GD_Keypad else { return nil }
        return Keyboard(properties: properties)
    }

    /// One entry per keyboard model, the built-in keyboard first, then by
    /// name.
    nonisolated static func list(_ keyboards: [Keyboard]) -> [Keyboard] {
        var seen = Set<Keyboard.ID>()
        return keyboards
            .sorted { ($0.isBuiltIn ? 0 : 1, $0.name.lowercased(), $0.vendorID, $0.productID)
                < ($1.isBuiltIn ? 0 : 1, $1.name.lowercased(), $1.vendorID, $1.productID) }
            .filter { seen.insert($0.id).inserted }
    }
}

extension Logger {
    static let keyboards = Logger(subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge", category: "keyboards")
}
