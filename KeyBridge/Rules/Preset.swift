/// A built-in set of rules the user can apply in one step, such as
/// "Windows Standard".
///
/// Presets make up the lower of two layers. The user's `Override`s sit on top
/// and always win, so applying a preset again never undoes a customization.
struct Preset: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var groups: [Group]

    /// Rules the user can switch on and off together, such as Editing or
    /// Finder.
    struct Group: Codable, Hashable, Identifiable, Sendable {
        var id: String
        var rules: [Rule]
    }

    var rules: [Rule] { groups.flatMap(\.rules) }
}

/// A change the user made on top of the preset layer.
enum Override: Codable, Hashable, Identifiable, Sendable {
    /// Replaces the preset rule with the same ID. The entry is shown as
    /// customized, and later preset updates no longer touch it. Switching a
    /// preset rule off is also a modification, with `isEnabled` set to false.
    case modified(rule: Rule)
    /// A rule the user created that no preset provides.
    case custom(rule: Rule)

    var rule: Rule {
        switch self {
        case .modified(let rule), .custom(let rule): rule
        }
    }

    var id: String { rule.id }
}
