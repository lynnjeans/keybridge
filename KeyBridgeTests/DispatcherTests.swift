import CoreGraphics
import Testing

@MainActor
@Suite struct DispatcherTests {
    func makeDispatcher(frontmost: String? = "com.apple.TextEdit") -> Dispatcher {
        let dispatcher = Dispatcher { frontmost }
        dispatcher.rules = BuiltInRules.all
        return dispatcher
    }

    func key(_ key: KeyCode, down: Bool, _ flags: CGEventFlags = [], repeat isRepeat: Bool = false) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: down))
        event.flags = flags
        if isRepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        return event
    }

    /// The replacement event, or nil if the disposition was something else.
    func replacement(_ disposition: Dispatcher.Disposition) -> CGEvent? {
        if case .replace(let event) = disposition { event } else { nil }
    }

    func isPassThrough(_ disposition: Dispatcher.Disposition) -> Bool {
        if case .passThrough = disposition { true } else { false }
    }

    func isConsumed(_ disposition: Dispatcher.Disposition) -> Bool {
        if case .consume = disposition { true } else { false }
    }

    @Test func controlCBecomesCommandC() throws {
        let dispatcher = makeDispatcher()
        let down = try #require(replacement(dispatcher.process(try key(.c, down: true, [.maskControl]), type: .keyDown)))
        #expect(down.keyCode == .c)
        #expect(Modifiers(flags: down.flags) == [.command])
        #expect(down.type == .keyDown)
        #expect(SyntheticEvent.isOurs(down))
    }

    @Test func releaseFollowsThePressEvenAfterControlIsLetGo() throws {
        let dispatcher = makeDispatcher()
        _ = dispatcher.process(try key(.c, down: true, [.maskControl]), type: .keyDown)
        let up = try #require(replacement(dispatcher.process(try key(.c, down: false), type: .keyUp)))
        #expect(up.keyCode == .c)
        #expect(up.type == .keyUp)
        #expect(Modifiers(flags: up.flags) == [.command])
        // The key is no longer held, so a plain C afterwards is left alone.
        #expect(isPassThrough(dispatcher.process(try key(.c, down: true), type: .keyDown)))
    }

    @Test func repeatsAreRemappedAndStayRepeats() throws {
        let dispatcher = makeDispatcher()
        _ = dispatcher.process(try key(.v, down: true, [.maskControl]), type: .keyDown)
        let repeated = try #require(replacement(
            dispatcher.process(try key(.v, down: true, [.maskControl], repeat: true), type: .keyDown)
        ))
        #expect(repeated.isAutorepeat)
        #expect(Modifiers(flags: repeated.flags) == [.command])
    }

    @Test func repeatsAfterControlIsLetGoAreSwallowed() throws {
        let dispatcher = makeDispatcher()
        _ = dispatcher.process(try key(.z, down: true, [.maskControl]), type: .keyDown)
        #expect(isConsumed(dispatcher.process(try key(.z, down: true, repeat: true), type: .keyDown)))
        #expect(replacement(dispatcher.process(try key(.z, down: false), type: .keyUp)) != nil)
    }

    @Test func repeatThatOnlyNowMatchesIsLeftAlone() throws {
        let dispatcher = makeDispatcher()
        #expect(isPassThrough(dispatcher.process(try key(.c, down: true), type: .keyDown)))
        #expect(isPassThrough(dispatcher.process(try key(.c, down: true, [.maskControl], repeat: true), type: .keyDown)))
        #expect(isPassThrough(dispatcher.process(try key(.c, down: false, [.maskControl]), type: .keyUp)))
    }

    @Test func unmatchedKeysPassThrough() throws {
        let dispatcher = makeDispatcher()
        #expect(isPassThrough(dispatcher.process(try key(.a, down: true, [.maskControl]), type: .keyDown)))
        #expect(isPassThrough(dispatcher.process(try key(.a, down: false, [.maskControl]), type: .keyUp)))
    }

    @Test func terminalsKeepControlC() throws {
        let dispatcher = makeDispatcher(frontmost: "com.apple.Terminal")
        #expect(isPassThrough(dispatcher.process(try key(.c, down: true, [.maskControl]), type: .keyDown)))
    }

    @Test func homeBecomesCommandLeftWithArrowFlags() throws {
        let dispatcher = makeDispatcher()
        let home = try key(.home, down: true, [.maskSecondaryFn])
        let down = try #require(replacement(dispatcher.process(home, type: .keyDown)))
        #expect(down.keyCode == .leftArrow)
        #expect(Modifiers(flags: down.flags) == [.command, .function])
        #expect(down.flags.contains(.maskNumericPad))
    }

    @Test func shiftHomeSelectsToLineStart() throws {
        let dispatcher = makeDispatcher()
        let home = try key(.home, down: true, [.maskShift, .maskSecondaryFn])
        let down = try #require(replacement(dispatcher.process(home, type: .keyDown)))
        #expect(Modifiers(flags: down.flags) == [.shift, .command, .function])
    }

    func button(_ number: Int, down: Bool, _ flags: CGEventFlags = []) throws -> CGEvent {
        let event = try #require(CGEvent(
            mouseEventSource: nil, mouseType: down ? .otherMouseDown : .otherMouseUp,
            mouseCursorPosition: .zero, mouseButton: .center
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number - 1))
        event.flags = flags
        return event
    }

    @Test func sideButtonBecomesACompleteKeystroke() throws {
        var posted: [CGEvent] = []
        let dispatcher = Dispatcher(frontmostBundleID: { "com.apple.Safari" }, post: { posted.append($0) })
        dispatcher.rules = BuiltInRules.all

        #expect(isConsumed(dispatcher.process(try button(4, down: true), type: .otherMouseDown)))
        #expect(posted.map(\.type) == [.keyDown, .keyUp])
        #expect(posted.allSatisfy { $0.keyCode == .leftBracket && Modifiers(flags: $0.flags) == [.command] })
        #expect(posted.allSatisfy(SyntheticEvent.isOurs))

        // The release is swallowed and triggers nothing more.
        #expect(isConsumed(dispatcher.process(try button(4, down: false), type: .otherMouseUp)))
        #expect(posted.count == 2)
    }

    @Test func forwardButtonMapsToCommandRightBracket() throws {
        var posted: [CGEvent] = []
        let dispatcher = Dispatcher(frontmostBundleID: { nil }, post: { posted.append($0) })
        dispatcher.rules = BuiltInRules.all
        _ = dispatcher.process(try button(5, down: true), type: .otherMouseDown)
        #expect(posted.first?.keyCode == .rightBracket)
    }

    @Test func unmappedButtonsPassThrough() throws {
        var posted: [CGEvent] = []
        let dispatcher = Dispatcher(frontmostBundleID: { nil }, post: { posted.append($0) })
        dispatcher.rules = BuiltInRules.all
        #expect(isPassThrough(dispatcher.process(try button(3, down: true), type: .otherMouseDown)))
        #expect(isPassThrough(dispatcher.process(try button(3, down: false), type: .otherMouseUp)))
        // A modified side button is a different trigger.
        #expect(isPassThrough(dispatcher.process(try button(4, down: true, [.maskShift]), type: .otherMouseDown)))
        #expect(isPassThrough(dispatcher.process(try button(4, down: false), type: .otherMouseUp)))
        #expect(posted.isEmpty)
    }

    @Test func modifierFlagsRoundTrip() {
        let all: Modifiers = [.control, .option, .shift, .command, .function]
        #expect(Modifiers(flags: CGEventFlags(all)) == all)
        #expect(Modifiers(flags: CGEventFlags([.option])) == [.option])
    }
}
