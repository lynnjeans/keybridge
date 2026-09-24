import CoreGraphics
import Foundation
import Testing

/// Rules that act on an open or save dialog (KB-217): they match only while
/// such a dialog has the keyboard, so their trigger stays free elsewhere.
@MainActor
@Suite struct FileDialogTests {
    private let jump = Rule(id: "dialog.finderFolder", trigger: .key(combo: KeyCombo([.control], .g)),
                            action: .fileDialog(.finderFolder))
    private let context = MatchContext(frontmostBundleID: "com.apple.TextEdit")

    // MARK: - Matching

    @Test func matchesOnlyInADialog() {
        let matcher = RuleMatcher(rules: [jump])
        #expect(matcher.match(jump.trigger, in: context, isInFileDialog: { true })?.id == jump.id)
        #expect(matcher.match(jump.trigger, in: context, isInFileDialog: { false }) == nil)
    }

    /// Outside a dialog the next rule on the same keys gets its turn, such as
    /// a custom rule the person made for ⌃G elsewhere.
    @Test func outsideADialogTheNextRuleOnTheKeysApplies() {
        let other = Rule(id: "custom.g", trigger: jump.trigger, action: .key(combo: KeyCombo([.command], .g)))
        let matcher = RuleMatcher(rules: [jump, other])
        #expect(matcher.match(jump.trigger, in: context, isInFileDialog: { false })?.id == "custom.g")
        #expect(matcher.match(jump.trigger, in: context, isInFileDialog: { true })?.id == jump.id)
    }

    /// Finding out means asking the front app, so it is asked only for keys
    /// a dialog rule is on, and once.
    @Test func theDialogIsAskedAboutOnlyForDialogRules() {
        var asked = 0
        let copy = Rule(id: "edit.copy", trigger: .key(combo: KeyCombo([.control], .c)),
                        action: .key(combo: KeyCombo([.command], .c)))
        let matcher = RuleMatcher(rules: [jump, copy])
        _ = matcher.match(copy.trigger, in: context, isInFileDialog: { asked += 1; return true })
        #expect(asked == 0)
        _ = matcher.match(jump.trigger, in: context, isInFileDialog: { asked += 1; return true })
        #expect(asked == 1)
    }

    /// The condition comes with the action, not the scope: a custom rule or a
    /// mouse button set to it cannot fire outside a dialog either.
    @Test func aMouseButtonSetToItAlsoWaitsForADialog() {
        let button = Rule(id: "custom.button", trigger: .mouseButton(number: 4), action: .fileDialog(.finderFolder))
        let matcher = RuleMatcher(rules: [button])
        #expect(matcher.match(button.trigger, in: context, isInFileDialog: { false }) == nil)
        #expect(matcher.match(button.trigger, in: context, isInFileDialog: { true })?.id == button.id)
    }

    // MARK: - The preset

    @Test func thePresetHasTheGroupOnByDefault() {
        let group = BuiltInRules.preset.groups.first { $0.id == "dialogs" }
        #expect(group?.isEnabledByDefault == true)
        #expect(group?.rules == [jump])
    }

    /// fn mode: fn+G, and in terminals too, since the fn version drops the
    /// terminal exception — harmless, as it only matches in a dialog.
    @Test func followsTheFnChoice() {
        let rules = ControlKey.function.apply(to: [jump])
        #expect(rules.map(\.trigger) == [.key(combo: KeyCombo([.function], .g))])
        #expect(rules.first?.action == .fileDialog(.finderFolder))
    }

    @Test func theActionIsSavedAndReadBack() throws {
        let data = try JSONEncoder().encode(jump)
        #expect(try JSONDecoder().decode(Rule.self, from: data) == jump)
        #expect(String(data: data, encoding: .utf8)?.contains("finderFolder") == true)
    }

    // MARK: - Dispatching

    @Test func theKeyIsSwallowedAndTheDialogActedOn() async throws {
        var acted: [FileDialogAction] = []
        var posted: [CGEvent] = []
        let dispatcher = Dispatcher(frontmostBundleID: { "com.apple.TextEdit" }, isInFileDialog: { true },
                                    post: { posted.append($0) }, fileDialog: { acted.append($0) })
        dispatcher.rules = [jump]
        let down = try #require(CGEvent(keyboardEventSource: nil, virtualKey: KeyCode.g.rawValue, keyDown: true))
        down.flags = .maskControl
        let up = try #require(CGEvent(keyboardEventSource: nil, virtualKey: KeyCode.g.rawValue, keyDown: false))
        #expect(isConsumed(dispatcher.process(down, type: .keyDown)))
        #expect(isConsumed(dispatcher.process(up, type: .keyUp)))
        // Carried out once the tap callback has returned.
        try await Task.sleep(for: .milliseconds(50))
        #expect(acted == [.finderFolder])
        #expect(posted.isEmpty)
    }

    @Test func outsideADialogTheKeyGoesThrough() throws {
        let dispatcher = Dispatcher(frontmostBundleID: { "com.apple.TextEdit" }, isInFileDialog: { false },
                                    fileDialog: { _ in Issue.record("acted outside a dialog") })
        dispatcher.rules = [jump]
        let down = try #require(CGEvent(keyboardEventSource: nil, virtualKey: KeyCode.g.rawValue, keyDown: true))
        down.flags = .maskControl
        if case .passThrough = dispatcher.process(down, type: .keyDown) {} else {
            Issue.record("⌃G outside a dialog was not let through")
        }
    }

    private func isConsumed(_ disposition: Dispatcher.Disposition) -> Bool {
        if case .consume = disposition { true } else { false }
    }
}
