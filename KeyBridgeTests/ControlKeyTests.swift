import Foundation
import Testing

@Suite struct ControlKeyTests {
    let rules = BuiltInRules.preset.groups.filter(\.isEnabledByDefault).flatMap(\.rules)

    func matcher(_ key: ControlKey) -> RuleMatcher {
        RuleMatcher(rules: key.apply(to: rules))
    }

    func match(_ key: ControlKey, _ combo: KeyCombo, in app: String = "com.apple.TextEdit") -> Action? {
        matcher(key).match(.key(combo: combo), in: MatchContext(frontmostBundleID: app))?.action
    }

    let copy = Action.key(combo: KeyCombo([.command], .c))

    @Test func ctrlIsTheDefault() {
        #expect(Configuration().controlKey == .control)
        #expect(ControlKey.control.apply(to: rules) == rules)
    }

    @Test func fnReplacesCtrl() {
        #expect(match(.function, KeyCombo([.function], .c)) == copy)
        #expect(match(.function, KeyCombo([.control], .c)) == nil, "Ctrl keeps its Mac meaning")
        #expect(match(.function, KeyCombo([.function, .shift], .t)) == .key(combo: KeyCombo([.shift, .command], .t)))
    }

    @Test func bothKeepsCtrlAndAddsFn() {
        #expect(match(.both, KeyCombo([.control], .c)) == copy)
        #expect(match(.both, KeyCombo([.function], .c)) == copy)
    }

    @Test func fnWorksInTerminalsWhereCtrlDoesNot() {
        #expect(match(.both, KeyCombo([.control], .c), in: "com.apple.Terminal") == nil)
        #expect(match(.both, KeyCombo([.function], .c), in: "com.apple.Terminal") == copy)
    }

    @Test func finderRulesStayInFinder() {
        #expect(match(.function, KeyCombo([.function], .v), in: "com.apple.finder")
                == .key(combo: KeyCombo([.option, .command], .v)))
    }

    @Test func keysThatReportFnThemselvesKeepCtrl() {
        // fn+← is Home on a MacBook, and fn+Home reads as Home.
        #expect(match(.function, KeyCombo([.control], .leftArrow)) == .key(combo: KeyCombo([.option], .leftArrow)))
        #expect(match(.function, KeyCombo([.control], .home)) == .key(combo: KeyCombo([.command], .upArrow)))
        #expect(match(.function, KeyCombo(.home)) == .key(combo: KeyCombo([.command], .leftArrow)))
    }

    @Test func otherRulesAreUntouched() {
        let untouched = rules.filter {
            if case .key(let combo) = $0.trigger { !combo.modifiers.contains(.control) } else { true }
        }
        let applied = ControlKey.function.apply(to: rules)
        for rule in untouched {
            #expect(applied.contains(rule), "\(rule.id)")
        }
    }

    @Test func idsStayUnique() {
        let ids = ControlKey.both.apply(to: rules).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func theChoiceIsSavedAndOptionalInOlderFiles() throws {
        var configuration = Configuration()
        configuration.controlKey = .function
        let data = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(Configuration.self, from: data).controlKey == .function)
        #expect(String(decoding: data, as: UTF8.self).contains(#""controlKey":"fn""#))

        let older = Data(#"{"schemaVersion": 1, "overrides": []}"#.utf8)
        #expect(try JSONDecoder().decode(Configuration.self, from: older).controlKey == .control)
    }

    @Test func aCustomizedTriggerFollowsTheChoiceToo() {
        var copy = rules.first { $0.id == "edit.copy" }!
        copy.trigger = .key(combo: KeyCombo([.control, .shift], .c))
        let applied = ControlKey.function.apply(to: [copy])
        #expect(applied.map(\.trigger) == [.key(combo: KeyCombo([.function, .shift], .c))])
    }
}
