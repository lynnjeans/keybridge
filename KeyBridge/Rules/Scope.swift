/// Where a rule applies: which applications, and which input devices.
///
/// A rule applies only when both filters let it through.
struct Scope: Codable, Hashable, Sendable {
    var applications: ApplicationFilter = .all
    var devices: DeviceFilter = .all

    static let everywhere = Scope()
}

/// Filters by the bundle identifier of the frontmost application.
enum ApplicationFilter: Codable, Hashable, Sendable {
    case all
    /// Only in these applications, as the Finder suite is limited to Finder.
    case only(bundleIDs: [String])
    /// Everywhere except these applications, as Ctrl+C is left alone in
    /// terminals, where it interrupts the running program.
    case except(bundleIDs: [String])
}

/// Filters by the physical device that produced the event.
///
/// Rules triggered by the Windows key need this: a PC keyboard's Win key
/// arrives as ⌘, so Win+V is indistinguishable from ⌘V on a Mac keyboard
/// except by the device it came from.
enum DeviceFilter: Codable, Hashable, Sendable {
    case all
    case only(devices: [DeviceID])
}

/// A USB or Bluetooth device, identified by vendor and product ID.
struct DeviceID: Codable, Hashable, Sendable {
    var vendorID: Int
    var productID: Int
}
