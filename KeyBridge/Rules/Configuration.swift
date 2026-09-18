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

    /// Preset groups that start off and the user has switched on. Absent
    /// from an older file means none, so this needs no migration either.
    var enabledGroups: Set<String> = []

    /// Which key the Windows Ctrl shortcuts are pressed with. Absent from an
    /// older file means Ctrl, so this needs no migration.
    var controlKey: ControlKey = .control

    /// The rules in effect: the preset's groups that are on, with the
    /// overrides on top, pressed with the chosen control key. A switched-off group contributes nothing, even where
    /// the user has customised one of its entries — the group switch is the
    /// broader, later decision.
    func effectiveRules(of preset: Preset) -> [Rule] {
        let enabled = preset.groups
            .filter(isEnabled(group:))
            .flatMap(\.rules)
        return controlKey.apply(to: effectiveRules(base: enabled))
    }

    /// Whether a group is switched on: the user's choice, or else the
    /// group's default.
    func isEnabled(group: Preset.Group) -> Bool {
        if enabledGroups.contains(group.id) { return true }
        if disabledGroups.contains(group.id) { return false }
        return group.isEnabledByDefault
    }

    /// Records the user's choice. Choosing a group's default forgets the
    /// choice, so a later release can change what the default is.
    mutating func setGroup(_ group: Preset.Group, enabled: Bool) {
        enabledGroups.remove(group.id)
        disabledGroups.remove(group.id)
        guard enabled != group.isEnabledByDefault else { return }
        if enabled {
            enabledGroups.insert(group.id)
        } else {
            disabledGroups.insert(group.id)
        }
    }

    /// Whether the user has changed the preset rule with this ID.
    func isCustomized(_ id: String) -> Bool {
        overrides.contains { if case .modified(let rule) = $0 { rule.id == id } else { false } }
    }

    /// Makes `rule` the user's version of the preset's `original`. Saving
    /// the preset's own version drops the override instead, so an entry
    /// edited back to what it was no longer counts as customized.
    mutating func setRule(_ rule: Rule, original: Rule) {
        precondition(rule.id == original.id, "An edit keeps the entry's ID")
        resetRule(rule.id)
        if rule != original {
            overrides.append(.modified(rule: rule))
        }
    }

    /// Drops the user's version of a preset rule, bringing the preset's back.
    mutating func resetRule(_ id: String) {
        overrides.removeAll { if case .modified(let rule) = $0 { rule.id == id } else { false } }
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
        case schemaVersion, overrides, disabledGroups, enabledGroups, controlKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overrides = try container.decodeIfPresent([Override].self, forKey: .overrides) ?? []
        disabledGroups = try container.decodeIfPresent(Set<String>.self, forKey: .disabledGroups) ?? []
        enabledGroups = try container.decodeIfPresent(Set<String>.self, forKey: .enabledGroups) ?? []
        controlKey = try container.decodeIfPresent(ControlKey.self, forKey: .controlKey) ?? .control
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .schemaVersion)
        try container.encode(overrides, forKey: .overrides)
        // Written in a stable order, so the file does not churn between saves.
        try container.encode(disabledGroups.sorted(), forKey: .disabledGroups)
        try container.encode(enabledGroups.sorted(), forKey: .enabledGroups)
        try container.encode(controlKey, forKey: .controlKey)
    }
}
