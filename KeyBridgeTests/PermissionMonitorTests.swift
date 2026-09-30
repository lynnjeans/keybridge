import IOKit.hid
import Testing

/// Stands in for the system's permission state.
final class FakePermissions: @unchecked Sendable {
    var accessibility = false
    var inputMonitoring = kIOHIDAccessTypeUnknown
    /// The permissions the code under test asked the system for, in order.
    var requests: [Permission] = []
    /// What a freshly started process would see; nil stands for a failed
    /// check, which leaves this process's own answers in place.
    var fresh: [Permission: PermissionStatus]?
    var freshReads = 0

    var service: PermissionService {
        PermissionService(
            isAccessibilityTrusted: { self.accessibility },
            inputMonitoringAccess: { self.inputMonitoring },
            requestInputMonitoring: {
                self.requests.append(.inputMonitoring)
                return self.inputMonitoring == kIOHIDAccessTypeGranted
            },
            readInFreshProcess: {
                self.freshReads += 1
                return self.fresh
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

    // MARK: Fresh-process reads (KB-236)

    /// While a permission is missing, every refresh asks a fresh process, so
    /// a grant the running process cannot see still shows.
    @Test func aGrantSeenOnlyByAFreshProcessShows() {
        let fake = FakePermissions()
        let monitor = PermissionMonitor(service: fake.service)
        fake.fresh = [.accessibility: .granted, .inputMonitoring: .granted]
        monitor.refresh()
        #expect(fake.freshReads == 1)
        #expect(monitor.allGranted)
    }

    /// With everything granted, a fresh process is asked only now and then,
    /// or when told to, and a revocation it sees wins over this process's
    /// stale yes.
    @Test func aRevocationShowsOnTheOccasionalFreshRead() {
        let fake = FakePermissions()
        fake.accessibility = true
        fake.inputMonitoring = kIOHIDAccessTypeGranted
        let monitor = PermissionMonitor(service: fake.service)
        fake.fresh = [.accessibility: .denied, .inputMonitoring: .granted]
        for _ in 1..<PermissionMonitor.freshReadInterval { monitor.refresh() }
        #expect(fake.freshReads == 0)
        #expect(monitor.allGranted)
        monitor.refresh()
        #expect(fake.freshReads == 1)
        #expect(monitor.status(of: .accessibility) == .denied)
    }

    @Test func aFreshReadCanBeAskedFor() {
        let fake = FakePermissions()
        fake.accessibility = true
        fake.inputMonitoring = kIOHIDAccessTypeGranted
        let monitor = PermissionMonitor(service: fake.service)
        fake.fresh = [.accessibility: .denied, .inputMonitoring: .granted]
        monitor.refresh(fresh: true)
        #expect(monitor.status(of: .accessibility) == .denied)
    }

    /// A failed fresh read leaves this process's own answers.
    @Test func aFailedFreshReadFallsBack() {
        let fake = FakePermissions()
        fake.accessibility = true
        let monitor = PermissionMonitor(service: fake.service)
        monitor.refresh()
        #expect(fake.freshReads == 1)
        #expect(monitor.status(of: .accessibility) == .granted)
    }

    @Test func theReportRoundTrips() {
        let fake = FakePermissions()
        fake.accessibility = true
        fake.inputMonitoring = kIOHIDAccessTypeDenied
        let text = PermissionService.report(fake.service)
        #expect(text == "accessibility=granted inputMonitoring=denied")
        #expect(PermissionService.parseReport(text) == [.accessibility: .granted, .inputMonitoring: .denied])
    }

    @Test func aGarbledReportIsRejected() {
        #expect(PermissionService.parseReport("") == nil)
        #expect(PermissionService.parseReport("accessibility=granted") == nil)
        #expect(PermissionService.parseReport("accessibility=maybe inputMonitoring=granted") == nil)
        #expect(PermissionService.parseReport("dyld: error") == nil)
    }
}
