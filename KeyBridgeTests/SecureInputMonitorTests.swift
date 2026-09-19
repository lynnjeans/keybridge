import Foundation
import Testing

@MainActor
@Suite struct SecureInputMonitorTests {
    final class State { var reading = SecureInputMonitor.Reading(isOn: false, pid: nil) }

    @Test func followsTheSystemState() {
        let state = State()
        let monitor = SecureInputMonitor { state.reading }
        let start = Date(timeIntervalSince1970: 1_000)

        monitor.refresh(now: start)
        #expect(monitor.holder == nil)

        state.reading = .init(isOn: true, pid: nil)
        monitor.refresh(now: start)
        #expect(monitor.holder?.since == start)
        monitor.refresh(now: start.addingTimeInterval(5))
        #expect(!monitor.isLingering, "Typing a password")

        monitor.refresh(now: start.addingTimeInterval(SecureInputMonitor.lingering))
        #expect(monitor.holder?.since == start, "Still the same holder, the clock keeps running")
        #expect(monitor.isLingering)

        state.reading = .init(isOn: false, pid: nil)
        monitor.refresh()
        #expect(monitor.holder == nil)
        #expect(!monitor.isLingering)
    }

    @Test func knownAppsGetAHowTo() {
        let terminal = SecureInputMonitor.Holder(appName: "Terminal", bundleID: "com.apple.Terminal", since: .now)
        #expect(terminal.switchOffHint?.contains("Secure Keyboard Entry") == true)
        let other = SecureInputMonitor.Holder(appName: "Safari", bundleID: "com.apple.Safari", since: .now)
        #expect(other.switchOffHint == nil)
    }
}
