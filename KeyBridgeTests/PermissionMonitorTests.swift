import IOKit.hid
import Testing

/// Stands in for the system's permission state.
final class FakePermissions: @unchecked Sendable {
    var accessibility = false
    var inputMonitoring = kIOHIDAccessTypeUnknown
    /// The permissions the code under test asked the system for, in order.
    var requests: [Permission] = []

    var service: PermissionService {
        PermissionService(
            isAccessibilityTrusted: { self.accessibility },
            inputMonitoringAccess: { self.inputMonitoring },
            requestInputMonitoring: {
                self.requests.append(.inputMonitoring)
                return self.inputMonitoring == kIOHIDAccessTypeGranted
            }
        )
    }
}

@MainActor
@Suite struct PermissionMonitorTests {
    @Test func startsWithTheCurrentState() {
        let fake = FakePermissions()
        fake.accessibility = true
        let monitor = PermissionMonitor(service: fake.service)
        #expect(monitor.status(of: .accessibility) == .granted)
        #expect(monitor.status(of: .inputMonitoring) == .notDetermined)
        #expect(!monitor.allGranted)
    }

    @Test func grantingIsReportedOnTheNextRefresh() {
        let fake = FakePermissions()
        let monitor = PermissionMonitor(service: fake.service)
        var reports: [Set<Permission>] = []
        monitor.onChange = { reports.append($0) }

        fake.accessibility = true
        fake.inputMonitoring = kIOHIDAccessTypeGranted
        monitor.refresh()

        #expect(reports == [[.accessibility, .inputMonitoring]])
        #expect(monitor.allGranted)
    }

    @Test func revokingIsReportedAndRollsTheStateBack() {
        let fake = FakePermissions()
        fake.accessibility = true
        fake.inputMonitoring = kIOHIDAccessTypeGranted
        let monitor = PermissionMonitor(service: fake.service)
        var reports: [Set<Permission>] = []
        monitor.onChange = { reports.append($0) }

        fake.accessibility = false
        monitor.refresh()

        #expect(reports == [[.accessibility]])
        #expect(monitor.status(of: .accessibility) == .denied)
        #expect(monitor.status(of: .inputMonitoring) == .granted)
        #expect(!monitor.allGranted)
    }

    @Test func unchangedStateReportsNothing() {
        let fake = FakePermissions()
        let monitor = PermissionMonitor(service: fake.service)
        var reports: [Set<Permission>] = []
        monitor.onChange = { reports.append($0) }
        monitor.refresh()
        monitor.refresh()
        #expect(reports.isEmpty)
    }

    // MARK: Asking for Input Monitoring outside the guide (KB-236)

    @Test func asksForInputMonitoringOnceAccessibilityIsGranted() {
        let fake = FakePermissions()
        let monitor = PermissionMonitor(service: fake.service)
        monitor.requestInputMonitoringIfUndecided()
        #expect(fake.requests.isEmpty)
        fake.accessibility = true
        monitor.refresh()
        fake.inputMonitoring = kIOHIDAccessTypeGranted
        monitor.requestInputMonitoringIfUndecided()
        // The request's answer is read straight away.
        #expect(fake.requests == [.inputMonitoring])
    }

    @Test func asksOnlyOncePerRun() {
        let fake = FakePermissions()
        fake.accessibility = true
        let monitor = PermissionMonitor(service: fake.service)
        monitor.requestInputMonitoringIfUndecided()
        monitor.requestInputMonitoringIfUndecided()
        #expect(fake.requests == [.inputMonitoring])
    }

    /// A refusal is the user's; asking again would do nothing anyway.
    @Test func doesNotAskAfterARefusal() {
        let fake = FakePermissions()
        fake.accessibility = true
        fake.inputMonitoring = kIOHIDAccessTypeDenied
        let monitor = PermissionMonitor(service: fake.service)
        monitor.requestInputMonitoringIfUndecided()
        #expect(fake.requests.isEmpty)
    }
}
