import Foundation
import IOKit.hid
import Testing

@MainActor
final class FakeTap: EventTapControlling {
    private(set) var isRunning = false
    private(set) var starts = 0
    private(set) var stops = 0

    func start() -> Bool {
        isRunning = true
        starts += 1
        return true
    }

    func stop() {
        isRunning = false
        stops += 1
    }
}

@MainActor
@Suite struct EngineControllerTests {
    let fake = FakePermissions()
    let tap = FakeTap()
    let defaults: UserDefaults

    init() {
        let suite = "EngineControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func grantAll() {
        fake.accessibility = true
        fake.inputMonitoring = kIOHIDAccessTypeGranted
    }

    func makeEngine() -> (EngineController, PermissionMonitor) {
        let monitor = PermissionMonitor(service: fake.service)
        let engine = EngineController(permissions: monitor, tap: tap, defaults: defaults)
        engine.update()
        return (engine, monitor)
    }

    @Test func runsWithEverythingGrantedAndOnByDefault() {
        grantAll()
        let (engine, _) = makeEngine()
        #expect(engine.isEnabled)
        #expect(engine.isActive)
        #expect(tap.isRunning)
    }

    @Test func waitsForEveryPermission() {
        fake.accessibility = true
        let (engine, monitor) = makeEngine()
        #expect(!engine.canEnable)
        #expect(!engine.isActive)

        fake.inputMonitoring = kIOHIDAccessTypeGranted
        monitor.refresh()
        #expect(engine.isActive)
        #expect(tap.starts == 1)
    }

    @Test func revokingAPermissionStopsAndGrantingResumes() {
        grantAll()
        let (engine, monitor) = makeEngine()

        fake.inputMonitoring = kIOHIDAccessTypeDenied
        monitor.refresh()
        #expect(!engine.isActive)
        #expect(tap.stops == 1)
        #expect(engine.isEnabled, "The user's choice survives the revocation")

        fake.inputMonitoring = kIOHIDAccessTypeGranted
        monitor.refresh()
        #expect(engine.isActive)
        #expect(tap.starts == 2)
    }

    @Test func masterSwitchStopsAndStarts() {
        grantAll()
        let (engine, _) = makeEngine()
        engine.isEnabled = false
        #expect(!engine.isActive)
        #expect(!tap.isRunning)
        engine.isEnabled = true
        #expect(engine.isActive)
    }

    @Test func switchedOffStaysOffAcrossLaunches() {
        grantAll()
        let (first, _) = makeEngine()
        first.isEnabled = false

        let (second, _) = makeEngine()
        #expect(!second.isEnabled)
        #expect(!second.isActive)
    }

    @Test func switchedOffIgnoresPermissionChanges() {
        grantAll()
        let (engine, monitor) = makeEngine()
        engine.isEnabled = false
        fake.accessibility = false
        monitor.refresh()
        fake.accessibility = true
        monitor.refresh()
        #expect(!engine.isActive)
        #expect(tap.starts == 1)
    }
}
