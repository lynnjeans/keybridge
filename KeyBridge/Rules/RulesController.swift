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
    @ObservationIgnored private let capture: ((@MainActor (KeyCombo) -> Void)?) -> Void

    /// - Parameters:
    ///   - apply: hands the engine the rules it should run with.
    ///   - capture: points the engine's key presses at a recorder, or back
    ///     at the rules with nil.
    init(
        preset: Preset = BuiltInRules.preset,
        store: ConfigurationStore = ConfigurationStore(),
        configuration: Configuration? = nil,
        capture: @escaping ((@MainActor (KeyCombo) -> Void)?) -> Void = { _ in },
        apply: @escaping ([Rule]) -> Void = { _ in }
    ) {
        self.preset = preset
        self.store = store
        self.apply = apply
        self.capture = capture
        // Computed into locals first: `self` is off limits until every
        // stored property has a value.
        let loaded = configuration ?? store.load().configuration
        let rules = loaded.effectiveRules(of: preset)
        self.configuration = loaded
        effectiveRules = rules
        apply(rules)
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

    /// The rules of one group, as shown under its card, whether or not the
    /// group is switched on.
    func rules(inGroup group: String) -> [Rule] {
        guard let group = preset.groups.first(where: { $0.id == group }) else { return [] }
        return configuration.effectiveRules(base: group.rules)
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

    /// Hands every key combination pressed to `onCombo`, read by the event
    /// tap before the system or any window sees it, until `stopRecording`.
    /// Recording Ctrl+C gets Ctrl+C rather than ⌘C, and fn+C gets fn+C
    /// rather than Control Center.
    func startRecording(_ onCombo: @escaping @MainActor (KeyCombo) -> Void) {
        isRecording = true
        capture(onCombo)
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
    }
}
