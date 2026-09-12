import CoreGraphics
import OSLog

/// The path every event takes through KeyBridge: work out what it triggers,
/// find the rule that applies in the current context, and act on it.
@MainActor
final class Dispatcher {
    enum Disposition {
        /// Let the original event continue to its destination.
        case passThrough
        /// Remove the original event; the rule's action replaces it.
        case consume
    }

    /// The effective rules. Until configuration and presets exist this stays
    /// empty outside the debug self-test.
    var rules: [Rule] = [] {
        didSet { matcher = RuleMatcher(rules: rules) }
    }

    private var matcher = RuleMatcher(rules: [])
    private let frontmost: FrontmostApplication

    init(frontmost: FrontmostApplication) {
        self.frontmost = frontmost
    }

    func process(_ event: CGEvent, type: CGEventType) -> Disposition {
        guard let trigger = Trigger(event: event, type: type) else { return .passThrough }
        let context = MatchContext(frontmostBundleID: frontmost.bundleID)
        guard let rule = matcher.match(trigger, in: context) else { return .passThrough }
        return perform(rule)
    }

    /// Carrying out actions arrives with the remap executor (KB-040). Until
    /// then a match is only recorded and the original event continues, so
    /// KeyBridge never swallows input it cannot yet replace.
    private func perform(_ rule: Rule) -> Disposition {
        #if DEBUG
        matchCounts[rule.id, default: 0] += 1
        #endif
        return .passThrough
    }

    #if DEBUG
    /// How often each rule matched since the last call. Rule IDs are part of
    /// KeyBridge's configuration, not user input, so they are safe to log.
    private var matchCounts: [String: Int] = [:]

    func takeMatchCounts() -> [String: Int] {
        defer { matchCounts = [:] }
        return matchCounts
    }
    #endif
}
