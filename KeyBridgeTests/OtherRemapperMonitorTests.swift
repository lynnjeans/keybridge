import Foundation
import Testing

@MainActor
@Suite struct OtherRemapperMonitorTests {
    typealias Process = OtherRemapperMonitor.RunningProcess
    final class State { var processes: [Process] = [] }

    static let finder = Process(bundleID: "com.apple.finder", executableName: "Finder")
    static let karabiner = Process(bundleID: "org.pqrs.Karabiner-Console-User-Server",
                                   executableName: "Karabiner-Console-User-Server")

    @Test func namesKarabinerWhileItRunsAndForgetsItWhenItQuits() {
        let state = State()
        let monitor = OtherRemapperMonitor { state.processes }

        state.processes = [Self.finder]
        monitor.refresh()
        #expect(monitor.running.isEmpty)

        state.processes = [Self.finder, Self.karabiner]
        monitor.refresh()
        #expect(monitor.running == ["Karabiner-Elements"])

        state.processes = [Self.finder]
        monitor.refresh()
        #expect(monitor.running.isEmpty)
    }

    @Test func karabinerSettingsAndDaemonsAloneAreNotRemapping() {
        // Left running after the user quits Karabiner-Elements (the daemons
        // run as root and are filtered out before this, but must not match
        // either), or open without the console server.
        let leftovers = [
            Process(bundleID: "org.pqrs.Karabiner-Elements.Settings", executableName: "Karabiner-Elements"),
            Process(bundleID: "org.pqrs.Karabiner-Core-Service", executableName: "Karabiner-Core-Service"),
            Process(bundleID: "org.pqrs.Karabiner-VirtualHIDDevice-Daemon", executableName: "Karabiner-VirtualHIDDevice-Daemon"),
        ]
        #expect(OtherRemapperMonitor.tools(in: leftovers).isEmpty)
    }

    @Test func helpersMatchByPrefixAndAgentsByName() {
        let processes = [
            Process(bundleID: "com.nuebling.mac-mouse-fix.helper", executableName: "Mac Mouse Fix Helper"),
            Process(bundleID: nil, executableName: "logioptionsplus_agent"),
            // A shared prefix that is not a bundle beneath it.
            Process(bundleID: "com.caldis.Mosaic", executableName: "Mosaic"),
        ]
        #expect(OtherRemapperMonitor.tools(in: processes) == ["Mac Mouse Fix", "Logi Options+"])
    }

    @Test func eachToolIsNamedOnceInListOrder() {
        let processes = [
            Process(bundleID: "com.pilotmoon.scroll-reverser", executableName: "Scroll Reverser"),
            Self.karabiner,
            Self.karabiner,
        ]
        #expect(OtherRemapperMonitor.tools(in: processes) == ["Karabiner-Elements", "Scroll Reverser"])
    }

    @Test func readsThisProcessFromTheSystem() {
        // The test runner itself is one of the user's processes.
        let processes = OtherRemapperMonitor.userProcesses()
        #expect(processes.count > 1)
        #expect(processes.contains { $0.executableName == ProcessInfo.processInfo.processName })
    }
}
