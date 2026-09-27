import CoreGraphics
import Foundation
import Testing

/// Ctrl+click as ⌘+click, as on Windows (KB-222).
@MainActor
@Suite struct CtrlClickTests {
    @Test func theChosenKeyBecomesCommand() {
        #expect(CtrlClick(controlKey: .function).rewrite([.maskSecondaryFn]) == .maskCommand)
        #expect(CtrlClick(controlKey: .control).rewrite([.maskControl]) == .maskCommand)
        #expect(CtrlClick(controlKey: .both).rewrite([.maskControl]) == .maskCommand)
        #expect(CtrlClick(controlKey: .both).rewrite([.maskSecondaryFn]) == .maskCommand)
    }

    /// In fn mode Ctrl+click keeps its Mac meaning, the shortcut menu.
    @Test func theOtherKeyIsLeftAlone() {
        #expect(CtrlClick(controlKey: .function).rewrite([.maskControl]) == nil)
        #expect(CtrlClick(controlKey: .control).rewrite([.maskSecondaryFn]) == nil)
        #expect(CtrlClick(controlKey: .both).rewrite([]) == nil)
        #expect(CtrlClick(controlKey: .both).rewrite([.maskShift]) == nil)
    }

    /// Ctrl+Shift+click on Windows extends a selection; ⇧ stays with ⌘.
    @Test func otherModifiersStay() {
        #expect(CtrlClick(controlKey: .control).rewrite([.maskControl, .maskShift]) == [.maskCommand, .maskShift])
    }

    // MARK: - Dispatching

    private func click(_ type: CGEventType, _ flags: CGEventFlags) throws -> CGEvent {
        let event = try #require(CGEvent(mouseEventSource: nil, mouseType: type,
                                         mouseCursorPosition: .zero, mouseButton: .left))
        event.flags = flags
        return event
    }

    @Test func pressAndReleaseGoOutAsCommandClick() throws {
        let dispatcher = Dispatcher(frontmostBundleID: { "com.apple.finder" })
        dispatcher.ctrlClick = CtrlClick(controlKey: .function)
        let down = try click(.leftMouseDown, .maskSecondaryFn)
        _ = dispatcher.process(down, type: .leftMouseDown)
        #expect(down.flags == .maskCommand)
        // fn let go of before the button: the release still carries ⌘.
        let up = try click(.leftMouseUp, [])
        _ = dispatcher.process(up, type: .leftMouseUp)
        #expect(up.flags == .maskCommand)
        // The next plain click is plain.
        let plain = try click(.leftMouseDown, [])
        _ = dispatcher.process(plain, type: .leftMouseDown)
        let plainUp = try click(.leftMouseUp, [])
        _ = dispatcher.process(plainUp, type: .leftMouseUp)
        #expect(plain.flags.isEmpty && plainUp.flags.isEmpty)
    }

    @Test func offLeavesClicksAlone() throws {
        let dispatcher = Dispatcher(frontmostBundleID: { "com.apple.finder" })
        let down = try click(.leftMouseDown, .maskControl)
        if case .passThrough = dispatcher.process(down, type: .leftMouseDown) {} else {
            Issue.record("a click was not let through")
        }
        #expect(down.flags == .maskControl)
    }

    /// The Dock click sees the click as it arrived.
    @Test func theDockClickSeesTheOriginalFlags() throws {
        let dispatcher = Dispatcher(frontmostBundleID: { "com.apple.finder" })
        dispatcher.ctrlClick = CtrlClick(controlKey: .control)
        var seen: CGEventFlags?
        dispatcher.leftMouse = { event, _ in seen = event.flags }
        _ = dispatcher.process(try click(.leftMouseDown, .maskControl), type: .leftMouseDown)
        #expect(seen == .maskControl)
    }

    // MARK: - The setting

    @Test func offByDefaultAndLeftOutOfTheFileWhileOff() throws {
        let configuration = Configuration()
        #expect(configuration.ctrlClickSelects == false)
        let data = try JSONEncoder().encode(configuration)
        #expect(String(data: data, encoding: .utf8)?.contains("ctrlClickSelects") == false)
        var on = configuration
        on.ctrlClickSelects = true
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(on)).ctrlClickSelects)
    }
}
