/// Where a rule applies: which applications, and which input devices.
///
/// A rule applies only when both filters let it through.
struct Scope: Hashable, Sendable {
    var applications: ApplicationFilter = .all
    var devices: DeviceFilter = .all
    /// Stands aside while the user types in a text field or answers a dialog.
    /// Finder's Enter-opens and Backspace-goes-up would otherwise break
    /// renaming a file or typing in the search field.
    var skipsTextInput = false

    static let everywhere = Scope()
}

// Written by hand so `skipsTextInput` is optional in the file: absent in older
// files, and left out when false, so existing rules encode as before.
extension Scope: Codable {
    private enum CodingKeys: String, CodingKey {
        case applications, devices, skipsTextInput
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applications = try container.decode(ApplicationFilter.self, forKey: .applications)
        devices = try container.decode(DeviceFilter.self, forKey: .devices)
        skipsTextInput = try container.decodeIfPresent(Bool.self, forKey: .skipsTextInput) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(applications, forKey: .applications)
        try container.encode(devices, forKey: .devices)
        if skipsTextInput {
            try container.encode(true, forKey: .skipsTextInput)
        }
    }
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
