import CoreGraphics
import Foundation
import Testing

/// Switching input sources without the system's switcher (SK-277).
@MainActor
@Suite struct InputSourceSwitcherTests {
    private typealias Source = InputSourceSwitcher.Source
    private let abc = Source(id: "com.apple.keylayout.ABC", isLayout: true)
    private let british = Source(id: "com.apple.keylayout.British", isLayout: true)
    private let pinyin = Source(id: "com.apple.inputmethod.SCIM.ITABC", isLayout: false)
    private let kana = Source(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", isLayout: false)

    // MARK: - Choosing

    @Test func abcAndPinyinSwitchBackAndForth() {
        let enabled = [abc, pinyin]
        #expect(InputSourceSwitcher.choose(current: abc, enabled: enabled, lastUsed: [:]) == pinyin)
        #expect(InputSourceSwitcher.choose(current: pinyin, enabled: enabled, lastUsed: [:]) == abc)
    }

    @Test func theInputMethodUsedLastIsChosen() {
        let enabled = [abc, kana, pinyin]
        #expect(InputSourceSwitcher.choose(current: abc, enabled: enabled, lastUsed: [false: pinyin.id]) == pinyin)
        #expect(InputSourceSwitcher.choose(current: abc, enabled: enabled, lastUsed: [false: kana.id]) == kana)
    }

    @Test func aSourceNoLongerEnabledIsPassedOver() {
        let enabled = [abc, kana]
        #expect(InputSourceSwitcher.choose(current: abc, enabled: enabled, lastUsed: [false: pinyin.id]) == kana)
    }

    @Test func theLayoutUsedLastIsChosenOnTheWayBack() {
        let enabled = [abc, british, pinyin]
        #expect(InputSourceSwitcher.choose(current: pinyin, enabled: enabled, lastUsed: [true: british.id]) == british)
    }

    @Test func withOneKindOnlyTheNextIsChosen() {
        #expect(InputSourceSwitcher.choose(current: abc, enabled: [abc, british], lastUsed: [:]) == british)
        #expect(InputSourceSwitcher.choose(current: british, enabled: [abc, british], lastUsed: [:]) == abc)
        #expect(InputSourceSwitcher.choose(current: abc, enabled: [abc], lastUsed: [:]) == nil)
    }

    // MARK: - The rule

    @Test func theActionIsWrittenByName() throws {
        let json = String(decoding: try JSONEncoder().encode(Action.switchInputSource), as: UTF8.self)
        #expect(json == #"{"switchInputSource":{}}"#)
        #expect(try JSONDecoder().decode(Action.self, from: Data(json.utf8)) == .switchInputSource)
    }

    final class Switches { var count = 0 }

    /// The rule the user asked for: Shift tapped alone.
    @Test func shiftTappedAloneSwitches() async throws {
        let switches = Switches()
        let dispatcher = Dispatcher(
            frontmostBundleID: { "com.apple.TextEdit" },
            switchInputSource: { switches.count += 1 },
            isSecureInputOn: { false }
        )
        dispatcher.rules = [Rule(id: "custom.shift", trigger: .key(combo: KeyCombo(.shift)), action: .switchInputSource)]
        let leftShift = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x02)

        func modifier(_ flags: CGEventFlags) throws -> CGEvent {
            let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: KeyCode.shift.rawValue, keyDown: true))
            event.type = .flagsChanged
            event.flags = flags
            return event
        }
        _ = dispatcher.process(try modifier(leftShift), type: .flagsChanged)
        _ = dispatcher.process(try modifier([]), type: .flagsChanged)
        try await Task.sleep(for: .milliseconds(50))
        #expect(switches.count == 1)

        // Shift+A types a capital and switches nothing.
        _ = dispatcher.process(try modifier(leftShift), type: .flagsChanged)
        let a = try #require(CGEvent(keyboardEventSource: nil, virtualKey: KeyCode.a.rawValue, keyDown: true))
        a.flags = leftShift
        _ = dispatcher.process(a, type: .keyDown)
        _ = dispatcher.process(try modifier([]), type: .flagsChanged)
        try await Task.sleep(for: .milliseconds(50))
        #expect(switches.count == 1)
    }
}
