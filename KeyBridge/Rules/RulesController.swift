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

    /// - Parameter apply: hands the engine the rules it should run with.
    init(
        preset: Preset = BuiltInRules.preset,
        store: ConfigurationStore = ConfigurationStore(),
        configuration: Configuration? = nil,
        apply: @escaping ([Rule]) -> Void = { _ in }
    ) {
        self.preset = preset
        self.store = store
        self.apply = apply
        // Computed into locals first: `self` is off limits until every
        // stored property has a value.
        let loaded = configuration ?? store.load().configuration
        let rules = loaded.effectiveRules(of: preset)
        self.configuration = loaded
        effectiveRules = rules
        apply(rules)
    }

    func isEnabled(group: String) -> Bool {
        configuration.isEnabled(group: group)
    }

    /// Switches a whole group on or off, saving and taking effect at once.
    func setGroup(_ group: String, enabled: Bool) {
        guard configuration.isEnabled(group: group) != enabled else { return }
        configuration.setGroup(group, enabled: enabled)
        Logger.configuration.notice(
            "Group \(group, privacy: .public) switched \(enabled ? "on" : "off", privacy: .public)"
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

    /// Other entries that react to the same trigger as `rule`, wherever they
    /// are and whether or not they are on: only one of them can win.
    func conflicts(with rule: Rule) -> [Rule] {
        configuration.effectiveRules(base: preset.rules)
            .filter { $0.id != rule.id && $0.trigger == rule.trigger }
    }

    /// While a shortcut is being recorded the engine stands aside, so the
    /// recorder sees what the user pressed rather than what it maps to:
    /// recording Ctrl+C must not arrive as ⌘C.
    var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            Logger.configuration.notice("Recording \(self.isRecording ? "started" : "ended", privacy: .public)")
            apply(isRecording ? [] : effectiveRules)
        }
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
        if !isRecording {
            apply(effectiveRules)
        }
    }
}
