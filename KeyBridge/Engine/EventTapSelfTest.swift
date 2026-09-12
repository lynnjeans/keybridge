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
