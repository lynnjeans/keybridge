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

    /// Which way mouse wheels scroll. Absent from an older file means the
    /// system's way, so this needs no migration.
    var wheelDirection: WheelDirection = .system

    /// Whether clicking the Dock icon of the app in front minimizes its
    /// window, as a taskbar button does on Windows. Absent from an older file
    /// means on, the default, so this needs no migration.
    var dockClickMinimizes = true

    /// The rules in effect: the user's custom rules, then the preset's groups
    /// that are on with the user's changes, pressed with the chosen control
    /// key. A switched-off group contributes nothing, even where the user has
    /// customised one of its entries — the group switch is the broader, later
    /// decision. Custom rules are taken as recorded: the control key is a
    /// setting for the preset.
    func effectiveRules(of preset: Preset) -> [Rule] {
        let enabled = preset.groups
            .filter(isEnabled(group:))
            .flatMap(\.rules)
        return customRules + controlKey.apply(to: presetRules(base: enabled))
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

    /// Puts the preset back as it ships: every group at its default — the
    /// Windows key group off, the rest on — and every changed entry back to
    /// the preset's version. The user's own rules stay, and so do the
    /// settings that are not part of the preset: the control key and the
    /// wheel direction.
    mutating func restoreDefaults() {
        disabledGroups = []
        enabledGroups = []
        overrides.removeAll { if case .modified = $0 { true } else { false } }
    }

    /// Whether `restoreDefaults()` would change nothing.
    var isDefault: Bool {
        disabledGroups.isEmpty && enabledGroups.isEmpty
            && !overrides.contains { if case .modified = $0 { true } else { false } }
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

    /// The rules in effect: the custom rules, then `base` with the user's
    /// changes.
    ///
    /// Custom rules come first so that, where one shares a trigger with a
    /// preset rule in the same scope, the user's own rule wins: the matcher
    /// keeps the given order between equally narrow scopes.
    func effectiveRules(base: [Rule]) -> [Rule] {
        customRules + presetRules(base: base)
    }

    /// `base` with the user's changes. A modified rule takes the place of the
    /// base rule with the same ID, so order and matching priority are kept;
    /// one whose ID the base no longer has is ignored. Re-applying presets
    /// while keeping customizations is KB-031.
    func presetRules(base: [Rule]) -> [Rule] {
        var modified: [String: Rule] = [:]
        for case .modified(let rule) in overrides {
            modified[rule.id] = rule
        }
        return base.map { modified[$0.id] ?? $0 }
    }

    /// Rules the user made that no preset provides, in the order made.
    var customRules: [Rule] {
        overrides.compactMap { if case .custom(let rule) = $0 { rule } else { nil } }
    }

    /// Adds a custom rule, or replaces the one with the same ID in place.
    mutating func setCustomRule(_ rule: Rule) {
        let custom = Override.custom(rule: rule)
        if let index = overrides.firstIndex(where: { if case .custom(let old) = $0 { old.id == rule.id } else { false } }) {
            overrides[index] = custom
        } else {
            overrides.append(custom)
        }
    }

    mutating func removeCustomRule(_ id: String) {
        overrides.removeAll { if case .custom(let rule) = $0 { rule.id == id } else { false } }
    }
}

// The version is written into the file but not kept in memory: by the time a
// `Configuration` exists, `ConfigurationStore` has already migrated it.
extension Configuration: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, overrides, disabledGroups, enabledGroups, controlKey, wheelDirection, dockClickMinimizes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overrides = try container.decodeIfPresent([Override].self, forKey: .overrides) ?? []
        disabledGroups = try container.decodeIfPresent(Set<String>.self, forKey: .disabledGroups) ?? []
        enabledGroups = try container.decodeIfPresent(Set<String>.self, forKey: .enabledGroups) ?? []
        controlKey = try container.decodeIfPresent(ControlKey.self, forKey: .controlKey) ?? .control
        wheelDirection = try container.decodeIfPresent(WheelDirection.self, forKey: .wheelDirection) ?? .system
        dockClickMinimizes = try container.decodeIfPresent(Bool.self, forKey: .dockClickMinimizes) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .schemaVersion)
        try container.encode(overrides, forKey: .overrides)
        // Written in a stable order, so the file does not churn between saves.
        try container.encode(disabledGroups.sorted(), forKey: .disabledGroups)
        try container.encode(enabledGroups.sorted(), forKey: .enabledGroups)
        try container.encode(controlKey, forKey: .controlKey)
        try container.encode(wheelDirection, forKey: .wheelDirection)
        try container.encode(dockClickMinimizes, forKey: .dockClickMinimizes)
    }
}
