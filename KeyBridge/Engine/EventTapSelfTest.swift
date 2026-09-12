#if DEBUG
import AppKit
import CoreGraphics
import OSLog

/// Debug-only self-tests, run by launching with an environment variable set.
///
/// KeyBridge posts the events itself because it holds the permission to do so.
/// A harness running from a terminal usually does not, and macOS silently drops
/// the events it posts.
@MainActor
enum EventTapSelfTest {
    static func runIfRequested(dispatcher: Dispatcher) {
        let environment = ProcessInfo.processInfo.environment
        if environment["KB_DEBUG_SELFTEST"] != nil { runTapTest() }
        if environment["KB_DEBUG_MATCHTEST"] != nil { runMatchTest(dispatcher) }
        if environment["KB_DEBUG_REMAPTEST"] != nil { runRemapTest(dispatcher) }
        if environment["KB_DEBUG_SCROLLTEST"] != nil { installScrollRules(dispatcher) }
    }

    /// For checking by hand that only mouse wheels trigger scroll rules:
    /// installs match-only rules for plain scrolling up and down. Scroll
    /// actions are not carried out yet, so these change nothing on screen.
    /// Scrolling with a mouse should log `Matched rules: selftest.scrollDown=…`;
    /// scrolling on a trackpad should log scroll events but no matches.
    private static func installScrollRules(_ dispatcher: Dispatcher) {
        dispatcher.rules = [ScrollDirection.up, .down].map { direction in
            Rule(id: "selftest.scroll\(direction.rawValue.capitalized)",
                 trigger: .scroll(direction: direction, modifiers: []),
                 action: .key(combo: KeyCombo(.f17)))
        }
        Logger.engine.notice("Scroll test: rules for plain scrolling up and down installed")
    }

    /// Checks what applications receive after remapping, through the
    /// downstream probe, with the test rule ⌃F19 → ⌥F18. Expected probe log
    /// (F18 also carries fn, as F-keys from the hardware do):
    /// 1. ⌃F19 held with two repeats, Ctrl released before F19:
    ///    F18 down, repeat, repeat, up, all [option+fn]. No F19 at all.
    /// 2. ⌃F19 held, Ctrl released, F19 still repeating, then released:
    ///    F18 down and up only; the repeat without Ctrl is swallowed.
    /// 3. F20, which no rule matches: F20 down and up, unchanged.
    /// 4. Mouse button 4, mapped to ⌥F17: F17 down and up, and no button 4.
    /// 5. Mouse button 6, which no rule matches: button 6 down and up.
    /// Steps 4 and 5 click at the pointer's position with those buttons;
    /// nothing reacts to buttons 4 or 6 unless a tool like Karabiner is set up
    /// to, and posted events bypass Karabiner.
    private static func runRemapTest(_ dispatcher: Dispatcher) {
        dispatcher.rules = [
            Rule(id: "selftest.remap", trigger: .key(combo: KeyCombo([.control], .f19)),
                 action: .key(combo: KeyCombo([.option], .f18))),
            Rule(id: "selftest.button", trigger: .mouseButton(number: 4),
                 action: .key(combo: KeyCombo([.option], .f17))),
        ]
        DownstreamProbe.start()

        Task {
            try? await Task.sleep(for: .seconds(1))
            Logger.engine.notice("Remap test 1: ⌃F19 with repeats, Ctrl released first")
            post(.f19, down: true, [.maskControl])
            post(.f19, down: true, [.maskControl], repeat: true)
            post(.f19, down: true, [.maskControl], repeat: true)
            post(.f19, down: false)

            try? await Task.sleep(for: .seconds(1))
            Logger.engine.notice("Remap test 2: Ctrl released while F19 repeats")
            post(.f19, down: true, [.maskControl])
            post(.f19, down: true, repeat: true)
            post(.f19, down: false)

            try? await Task.sleep(for: .seconds(1))
            Logger.engine.notice("Remap test 3: F20, no rule")
            post(.f20, down: true)
            post(.f20, down: false)

            try? await Task.sleep(for: .seconds(1))
            Logger.engine.notice("Remap test 4: mouse button 4, mapped")
            click(button: 4)

            try? await Task.sleep(for: .seconds(1))
            Logger.engine.notice("Remap test 5: mouse button 6, no rule")
            click(button: 6)
        }
    }

    private static func click(button number: Int) {
        let location = CGEvent(source: nil)?.location ?? .zero
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let event = CGEvent(
                mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: location, mouseButton: .center
            ) else { continue }
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number - 1))
            event.post(tap: .cgSessionEventTap)
        }
    }

    private static func post(_ key: KeyCode, down: Bool, _ flags: CGEventFlags = [], repeat isRepeat: Bool = false) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: down) else { return }
        event.flags = flags
        if isRepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event.post(tap: .cgSessionEventTap)
    }

    /// Checks the tap's robustness features with zero-delta scrolls, so
    /// nothing on screen moves:
    /// 1. Five events through `SyntheticEvent.post`, which the tap should
    ///    report as its own and leave untouched.
    /// 2. One plain event. With KB_DEBUG_STALL_ONCE also set, it stalls the
    ///    tap long enough for macOS to disable it.
    /// 3. Three plain events after the recovery window, which the tap should
    ///    still receive.
    private static func runTapTest() {
        Task {
            Logger.eventTap.notice("Self-test: posting 5 own events")
            for _ in 0..<5 {
                if let event = zeroScroll() { SyntheticEvent.post(event) }
            }

            try? await Task.sleep(for: .milliseconds(500))
            Logger.eventTap.notice("Self-test: posting 1 plain event")
            zeroScroll()?.post(tap: .cgSessionEventTap)

            try? await Task.sleep(for: .seconds(5))
            Logger.eventTap.notice("Self-test: posting 3 plain events")
            for _ in 0..<3 {
                zeroScroll()?.post(tap: .cgSessionEventTap)
            }
        }
    }

    /// Checks rule matching end to end with test rules on F19, a key nothing
    /// uses by default, and the expected counts per rule in the log:
    /// 1. Three F19 presses with Finder in front: `selftest.finder` = 3.
    /// 2. Three with the previously frontmost app back in front:
    ///    `selftest.any` = 3. KeyBridge cannot use itself here: macOS does not
    ///    let a menu bar app without windows become frontmost.
    /// 3. Three F20 presses, for which no rule exists: no match.
    /// Matching only records for now, so the presses still reach the app.
    private static func runMatchTest(_ dispatcher: Dispatcher) {
        let previous = NSWorkspace.shared.frontmostApplication
        dispatcher.rules = [
            Rule(id: "selftest.any", trigger: .key(combo: KeyCombo(.f19)),
                 action: .key(combo: KeyCombo(.f18))),
            Rule(id: "selftest.finder", trigger: .key(combo: KeyCombo(.f19)),
                 action: .key(combo: KeyCombo(.f17)),
                 scope: Scope(applications: .only(bundleIDs: ["com.apple.finder"]))),
        ]

        Task {
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == "com.apple.finder" }?
                .activate()
            try? await Task.sleep(for: .seconds(1))
            Logger.engine.notice("Match test: 3 × F19 (expect selftest.finder)")
            press(.f19, times: 3)

            try? await Task.sleep(for: .seconds(1))
            if previous?.bundleIdentifier == "com.apple.finder" {
                Logger.engine.notice("Match test: Finder was already in front; step 2 will match selftest.finder")
            }
            previous?.activate()
            try? await Task.sleep(for: .seconds(1))
            Logger.engine.notice("Match test: 3 × F19 (expect selftest.any)")
            press(.f19, times: 3)

            try? await Task.sleep(for: .seconds(1))
            Logger.engine.notice("Match test: 3 × F20 (expect no match)")
            press(.f20, times: 3)
        }
    }

    private static func press(_ key: KeyCode, times: Int) {
        for _ in 0..<times {
            for down in [true, false] {
                CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: down)?
                    .post(tap: .cgSessionEventTap)
            }
        }
    }

    private static func zeroScroll() -> CGEvent? {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)
    }
}
#endif
