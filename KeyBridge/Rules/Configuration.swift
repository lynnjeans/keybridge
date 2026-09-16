/// What the user has changed on top of the built-in rules: the contents of the
/// configuration file.
///
/// Only the user's layer is stored. The preset layer ships with the app, so a
/// new release can improve it without touching anyone's file.
struct Configuration: Hashable, Sendable {
    /// The version of the file format this build writes. Raise it, and add a
    /// step to `ConfigurationStore.migrations`, whenever the encoded form
    /// changes; `RuleModelTests.ruleEncodingIsStable` catches such changes.
    static let currentVersion = 1

    var overrides: [Override] = []

    /// Preset groups the user has switched off. Absent from an older file
    /// means every group is on, so this needs no migration.
    var disabledGroups: Set<String> = []

    /// The rules in effect: the preset's groups the user has left on, with
    /// the overrides on top. A switched-off group contributes nothing, even
    /// where the user has customised one of its entries — the group switch is
    /// the broader, later decision.
    func effectiveRules(of preset: Preset) -> [Rule] {
        let enabled = preset.groups
            .filter { !disabledGroups.contains($0.id) }
            .flatMap(\.rules)
        return effectiveRules(base: enabled)
    }

    /// Whether a group is switched on. Unknown groups count as on.
    func isEnabled(group: String) -> Bool {
        !disabledGroups.contains(group)
    }

    mutating func setGroup(_ group: String, enabled: Bool) {
        if enabled {
            disabledGroups.remove(group)
        } else {
            disabledGroups.insert(group)
        }
    }

    /// The rules in effect: `base` with the user's overrides on top.
    ///
    /// A modified rule takes the place of the base rule with the same ID, so
    /// order and matching priority are kept; one whose ID the base no longer
    /// has is ignored. Custom rules follow the base rules. Re-applying presets
    /// while keeping customizations is KB-031.
    func effectiveRules(base: [Rule]) -> [Rule] {
        var modified: [String: Rule] = [:]
        var custom: [Rule] = []
        for override in overrides {
            switch override {
            case .modified(let rule): modified[rule.id] = rule
            case .custom(let rule): custom.append(rule)
            }
        }
        return base.map { modified[$0.id] ?? $0 } + custom
    }
}

// The version is written into the file but not kept in memory: by the time a
// `Configuration` exists, `ConfigurationStore` has already migrated it.
extension Configuration: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, overrides, disabledGroups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overrides = try container.decodeIfPresent([Override].self, forKey: .overrides) ?? []
        disabledGroups = try container.decodeIfPresent(Set<String>.self, forKey: .disabledGroups) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .schemaVersion)
        try container.encode(overrides, forKey: .overrides)
        // Written in a stable order, so the file does not churn between saves.
        try container.encode(disabledGroups.sorted(), forKey: .disabledGroups)
    }
}
