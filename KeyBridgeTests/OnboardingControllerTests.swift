import Foundation
import IOKit.hid
import Testing

@MainActor
@Suite struct OnboardingControllerTests {
    let fake = FakePermissions()
    let defaults: UserDefaults

    /// Every URL the guide sent the user to, and every time it was opened.
    final class Record {
        var urls: [URL] = []
        var presentations = 0
    }
    let record = Record()

    init() {
        let suite = "OnboardingControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func grantAll() {
        fake.accessibility = true
        fake.inputMonitoring = kIOHIDAccessTypeGranted
    }

    func makeController() -> (OnboardingController, PermissionMonitor) {
        let monitor = PermissionMonitor(service: fake.service)
        let controller = OnboardingController(
            permissions: monitor,
            service: fake.service,
            defaults: defaults,
            openURL: { [record] in record.urls.append($0) },
            presentGuide: { [record] in record.presentations += 1 }
        )
        return (controller, monitor)
    }

    @Test func startsAtAccessibilityWithNothingGranted() {
        let (controller, _) = makeController()
        #expect(controller.shouldOpenAtLaunch())
        #expect(controller.step == .accessibility)
        #expect(controller.step.number == 1)
    }

    @Test func advancesOnItsOwnAsPermissionsAreGranted() {
        let (controller, monitor) = makeController()

        fake.accessibility = true
        monitor.refresh()
        #expect(controller.step == .inputMonitoring, "The grant moves the guide on with no interaction")

        fake.inputMonitoring = kIOHIDAccessTypeGranted
        monitor.refresh()
        #expect(controller.step == .ready)
        #expect(record.presentations == 0, "Advancing opens nothing; the window is already up")
    }

    @Test func stepsBackWhenAPermissionIsRevoked() {
        grantAll()
        let (controller, monitor) = makeController()
        #expect(controller.step == .ready)

        fake.accessibility = false
        monitor.refresh()
        #expect(controller.step == .accessibility)
    }

    @Test func inputMonitoringIsAskedForEvenWhenNeverDetermined() {
        fake.accessibility = true
        let (controller, _) = makeController()
        #expect(fake.inputMonitoring == kIOHIDAccessTypeUnknown)
        #expect(controller.step == .inputMonitoring)
    }

    @Test func opensTheAuthorizationPaneForTheCurrentStep() {
        let (controller, monitor) = makeController()
        controller.openSettings()
        #expect(fake.requests.isEmpty, "Accessibility is never prompted for; the launch check lists KeyBridge")
        #expect(record.urls == [Permission.accessibility.settingsURL])
        #expect(record.urls.last?.absoluteString.contains("Privacy_Accessibility") == true)

        fake.accessibility = true
        monitor.refresh()
        controller.openSettings()
        #expect(fake.requests == [.inputMonitoring], "Requesting is what puts KeyBridge in this list")
        #expect(record.urls.last == Permission.inputMonitoring.settingsURL)
        #expect(record.urls.last?.absoluteString.contains("Privacy_ListenEvent") == true)
    }

    @Test func theClosingStepHasNothingToOpen() {
        grantAll()
        let (controller, _) = makeController()
        controller.openSettings()
        #expect(fake.requests.isEmpty)
        #expect(record.urls.isEmpty)
    }

    @Test func doesNotComeBackOnceCompleted() {
        let (first, _) = makeController()
        #expect(first.shouldOpenAtLaunch())
        first.complete()
        #expect(first.hasCompleted)

        let (second, _) = makeController()
        #expect(!second.shouldOpenAtLaunch(), "Still unauthorized, but the user has been through the guide")
    }

    @Test func aFirstRunWithEverythingGrantedIsSilentlyDone() {
        grantAll()
        let (controller, _) = makeController()
        #expect(!controller.shouldOpenAtLaunch())
        #expect(controller.hasCompleted)
    }

    @Test func theLaunchDecisionIsMadeOnlyOnce() {
        let (controller, _) = makeController()
        #expect(controller.shouldOpenAtLaunch())
        #expect(!controller.shouldOpenAtLaunch(), "Put aside once, it does not come back mid-run")
    }

    @Test func canBeOpenedAgainAfterCompleting() {
        let (controller, _) = makeController()
        controller.complete()
        controller.open()
        #expect(record.presentations == 1, "The menu bar and the Overview lead back in")
    }
}
