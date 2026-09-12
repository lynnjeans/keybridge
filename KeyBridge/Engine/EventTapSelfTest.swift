#if DEBUG
import CoreGraphics
import Foundation
import OSLog

/// Debug-only self-test for the tap's robustness features, run by launching
/// with KB_DEBUG_SELFTEST in the environment.
///
/// KeyBridge posts the events itself because it holds the permission to do so.
/// A harness running from a terminal usually does not, and macOS silently drops
/// the events it posts.
///
/// The sequence uses zero-delta scrolls, so nothing on screen moves:
/// 1. Five events through `SyntheticEvent.post`, which the tap should report as
///    its own and leave untouched.
/// 2. One plain event. With KB_DEBUG_STALL_ONCE also set, it stalls the tap
///    long enough for macOS to disable it.
/// 3. Three plain events after the recovery window, which the tap should still
///    receive.
@MainActor
enum EventTapSelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["KB_DEBUG_SELFTEST"] != nil else { return }

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

    private static func zeroScroll() -> CGEvent? {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)
    }
}
#endif
