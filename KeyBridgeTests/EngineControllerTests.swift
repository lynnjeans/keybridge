import Foundation
import IOKit.hid
import Testing

@MainActor
final class FakeTap: EventTapControlling {
    private(set) var isRunning = false
    var onGiveUp: ((TapGiveUpReason) -> Void)?
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

    @Test func aPauseStopsTheEngineUntilResumed() {
        grantAll()
        let (engine, _) = makeEngine()
        engine.pause(for: nil)
        #expect(engine.isPaused && !engine.isActive && !tap.isRunning)
        #expect(engine.isEnabled, "The master switch stays on")

        engine.resume()
        #expect(!engine.isPaused && engine.isActive && tap.isRunning)
    }

    @Test func aTimedPauseEndsByItself() {
        grantAll()
        let (engine, _) = makeEngine()
        engine.pause(for: 300)
        let until = try! #require(engine.pausedUntil)
        engine.resumeIfDue(now: until.addingTimeInterval(-1))
        #expect(engine.isPaused, "Not yet")
        engine.resumeIfDue(now: until)
        #expect(!engine.isPaused && tap.isRunning)
    }

    @Test func aPauseIsNotRemembered() {
        grantAll()
        let (engine, _) = makeEngine()
        engine.pause(for: nil)
        let (relaunched, _) = makeEngine()
        #expect(!relaunched.isPaused)
    }

    @Test func permissionsComingBackDoNotEndAPause() {
        grantAll()
        let (engine, _) = makeEngine()
        engine.pause(for: nil)
        engine.update()
        #expect(!tap.isRunning)
    }

    // MARK: A tap the system keeps disabling (KB-236)

    /// Accessibility revoked while running: the tap stops, the permission
    /// shows as missing, and the engine returns once it is granted again,
    /// without a pause to end.
    @Test func aLostPermissionStopsTheTapUntilGranted() {
        grantAll()
        let (engine, _) = makeEngine()
        fake.accessibility = false
        tap.onGiveUp?(.permissionLost)
        #expect(!tap.isRunning)
        #expect(!engine.isActive)
        #expect(!engine.isPaused)
        #expect(!engine.canEnable)
        fake.accessibility = true
        engine.permissions.refresh()
        #expect(engine.isActive)
    }

    /// A tap that keeps timing out with every permission in place pauses the
    /// engine, so it is not started straight back into the same stall.
    @Test func aTapThatKeepsTimingOutPausesTheEngine() {
        grantAll()
        let (engine, _) = makeEngine()
        tap.onGiveUp?(.keepsTimingOut)
        #expect(!tap.isRunning)
        #expect(engine.isPaused)
        #expect(!engine.isActive)
        engine.resume()
        #expect(engine.isActive)
    }
}

@Suite struct TapBreakerTests {
    /// Whether re-enabling was allowed after each disable, in order.
    private func answers(_ times: [TimeInterval], breaker: inout TapBreaker) -> [Bool] {
        times.map { breaker.recordDisable(at: $0) }
    }

    @Test func allowsOccasionalDisables() {
        var breaker = TapBreaker()
        #expect(answers([0, 40, 80, 120], breaker: &breaker) == [true, true, true, true])
    }

    @Test func tripsOnTheThirdWithinTheWindow() {
        var breaker = TapBreaker()
        #expect(answers([100, 101, 102], breaker: &breaker) == [true, true, false])
    }

    /// Only disables within the last 30 s count.
    @Test func oldDisablesAgeOut() {
        var breaker = TapBreaker()
        #expect(answers([0, 20, 31, 40], breaker: &breaker) == [true, true, true, false])
    }

    @Test func resetForgets() {
        var breaker = TapBreaker()
        _ = answers([0, 1], breaker: &breaker)
        breaker.reset()
        #expect(answers([2], breaker: &breaker) == [true])
    }
}
