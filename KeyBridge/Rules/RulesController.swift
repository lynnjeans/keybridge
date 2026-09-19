import Observation
import OSLog

/// Holds the rules the app runs with: the preset, the user's configuration on
/// top of it, and the engine's copy of the result.
///
/// Every change made in the UI goes through here, so saving the file and
/// refreshing the engine always happen together and in that order — a change
/// the user can see is a change already on disk.
@MainActor
@Observable
final class RulesController {
    let preset: Preset

    private(set) var configuration: Configuration

    /// The rules in effect, recomputed on every change.
    private(set) var effectiveRules: [Rule]

    @ObservationIgnored private let store: ConfigurationStore
    @ObservationIgnored private let apply: ([Rule]) -> Void
    @ObservationIgnored private let applyWheelDirection: (WheelDirection) -> Void
    @ObservationIgnored private let capture: ((@MainActor (Trigger) -> Void)?) -> Void

    /// - Parameters:
    ///   - apply: hands the engine the rules it should run with.
    ///   - applyWheelDirection: tells the engine which way wheels scroll.
    ///   - capture: points the engine's key presses at a recorder, or back
    ///     at the rules with nil.
    init(
        preset: Preset = BuiltInRules.preset,
        store: ConfigurationStore = ConfigurationStore(),
        configuration: Configuration? = nil,
        capture: @escaping ((@MainActor (Trigger) -> Void)?) -> Void = { _ in },
        applyWheelDirection: @escaping (WheelDirection) -> Void = { _ in },
        apply: @escaping ([Rule]) -> Void = { _ in }
    ) {
        self.preset = preset
        self.store = store
        self.apply = apply
        self.applyWheelDirection = applyWheelDirection
        self.capture = capture
        // Computed into locals first: `self` is off limits until every
        // stored property has a value.
        let loaded = configuration ?? store.load().configuration
        let rules = loaded.effectiveRules(of: preset)
        self.configuration = loaded
        effectiveRules = rules
        apply(rules)
        applyWheelDirection(loaded.wheelDirection)
    }

    func isEnabled(group: String) -> Bool {
        guard let group = preset.groups.first(where: { $0.id == group }) else { return false }
        return configuration.isEnabled(group: group)
    }

    /// Switches a whole group on or off, saving and taking effect at once.
    func setGroup(_ id: String, enabled: Bool) {
        guard let group = preset.groups.first(where: { $0.id == id }),
              configuration.isEnabled(group: group) != enabled else { return }
        configuration.setGroup(group, enabled: enabled)
        Logger.configuration.notice(
            "Group \(id, privacy: .public) switched \(enabled ? "on" : "off", privacy: .public)"
        )
        commit()
    }

    var wheelDirection: WheelDirection {
        configuration.wheelDirection
    }

    func setWheelDirection(_ direction: WheelDirection) {
        guard configuration.wheelDirection != direction else { return }
        configuration.wheelDirection = direction
        Logger.configuration.notice("Wheel direction: \(direction.rawValue, privacy: .public)")
        commit()
    }

    var controlKey: ControlKey {
        configuration.controlKey
    }

    /// Chooses the key the Ctrl shortcuts are pressed with, saving and taking
    /// effect at once.
    func setControlKey(_ key: ControlKey) {
        guard configuration.controlKey != key else { return }
        configuration.controlKey = key
        Logger.configuration.notice("Control key: \(key.rawValue, privacy: .public)")
        commit()
    }

    /// The modifiers held while scrolling to zoom, as the zoom rules have
    /// them.
    var zoomModifiers: Modifiers {
        for rule in rules(inGroup: "scroll") {
            if case .scroll(_, let modifiers) = rule.trigger { return modifiers }
        }
        return []
    }

    /// Changes the zoom modifier on both zoom rules. Choosing the preset's
    /// fn again drops the customization.
    func setZoomModifiers(_ modifiers: Modifiers) {
        for var rule in rules(inGroup: "scroll") {
            guard case .scroll(let direction, _) = rule.trigger else { continue }
            rule.trigger = .scroll(direction: direction, modifiers: modifiers)
            update(rule)
        }
    }

    /// How many rules are in effect and switched on.
    var activeRuleCount: Int {
        effectiveRules.filter(\.isEnabled).count
    }

    /// How many preset entries the user has changed.
    var customizedCount: Int {
        configuration.overrides.filter { if case .modified = $0 { true } else { false } }.count
    }

    /// Apps that rules in effect leave alone, such as terminals for Ctrl+C.
    var exceptionApps: Set<String> {
        var apps: Set<String> = []
        for rule in effectiveRules where rule.isEnabled {
            if case .except(let bundleIDs) = rule.scope.applications { apps.formUnion(bundleIDs) }
        }
        return apps
    }

    /// The rules of one group, as shown under its card, whether or not the
    /// group is switched on.
    func rules(inGroup group: String) -> [Rule] {
        guard let group = preset.groups.first(where: { $0.id == group }) else { return [] }
        return configuration.presetRules(base: group.rules)
    }

    /// The user's own rules, in the order made.
    var customRules: [Rule] {
        configuration.customRules
    }

    /// Adds a custom rule or saves changes to one, taking effect at once.
    func saveCustomRule(_ rule: Rule) {
        let before = configuration
        configuration.setCustomRule(rule)
        guard configuration != before else { return }
        Logger.configuration.notice("Custom rule \(rule.id, privacy: .public) saved")
        commit()
    }

    func deleteCustomRule(_ id: String) {
        let before = configuration
        configuration.removeCustomRule(id)
        guard configuration != before else { return }
        Logger.configuration.notice("Custom rule \(id, privacy: .public) deleted")
        commit()
    }

    /// The preset's version of an entry, before any change by the user.
    func original(of id: String) -> Rule? {
        preset.rules.first { $0.id == id }
    }

    func isCustomized(_ id: String) -> Bool {
        configuration.isCustomized(id)
    }

    /// Saves the user's version of a preset entry and puts it into effect.
    func update(_ rule: Rule) {
        guard let original = original(of: rule.id) else { return }
        let before = configuration
        configuration.setRule(rule, original: original)
        guard configuration != before else { return }
        Logger.configuration.notice(
            "Rule \(rule.id, privacy: .public) \(self.isCustomized(rule.id) ? "customized" : "back to default", privacy: .public)"
        )
        commit()
    }

    /// Brings back the preset's version of an entry.
    func reset(_ id: String) {
        guard isCustomized(id) else { return }
        configuration.resetRule(id)
        Logger.configuration.notice("Rule \(id, privacy: .public) reset")
        commit()
    }

    /// Other entries that react to the same trigger in the same apps, whether
    /// or not they are on: only one of them can win. A narrower app scope is
    /// no conflict — Ctrl+V moving files in Finder and pasting elsewhere is
    /// the point.
    func conflicts(with rule: Rule) -> [Rule] {
        configuration.effectiveRules(base: preset.rules).filter {
            $0.id != rule.id && $0.trigger == rule.trigger
                && $0.scope.applications == rule.scope.applications
        }
    }

    /// Whether the rule editor is recording a shortcut.
    private(set) var isRecording = false

    /// Hands every key combination and extra mouse button pressed to
    /// `onTrigger`, read by the event tap before the system or any window
    /// sees it, until `stopRecording`. Recording Ctrl+C gets Ctrl+C rather
    /// than ⌘C, and fn+C gets fn+C rather than Control Center.
    func startRecording(_ onTrigger: @escaping @MainActor (Trigger) -> Void) {
        isRecording = true
        capture(onTrigger)
        Logger.configuration.notice("Recording started")
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        capture(nil)
        Logger.configuration.notice("Recording ended")
    }

    private func commit() {
        effectiveRules = configuration.effectiveRules(of: preset)
        do {
            try store.save(configuration)
        } catch {
            // The engine still follows the change; only the file is behind.
            Logger.configuration.error(
                "Could not save the configuration: \(String(describing: error), privacy: .public)"
            )
        }
        apply(effectiveRules)
        applyWheelDirection(configuration.wheelDirection)
    }
}
