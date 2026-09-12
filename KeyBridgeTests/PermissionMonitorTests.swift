import IOKit.hid
import Testing

/// Stands in for the system's permission state.
final class FakePermissions: @unchecked Sendable {
    var accessibility = false
    var inputMonitoring = kIOHIDAccessTypeUnknown

    var service: PermissionService {
        PermissionService(
            isAccessibilityTrusted: { self.accessibility },
            inputMonitoringAccess: { self.inputMonitoring }
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
}
