import Foundation
import OSLog
import Observation

/// What `EngineController` needs from the event tap; lets tests stand in for it.
@MainActor
protocol EventTapControlling: AnyObject {
    var isRunning: Bool { get }
    @discardableResult func start() -> Bool
    func stop()
}

/// Decides whether KeyBridge's engine runs: only while the user has it
/// switched on and every permission is granted.
///
/// Input Monitoring counts too, even though the tap can be created without
/// it: the system would then withhold plain key presses, and a half-working
/// KeyBridge that remaps clicks but not Ctrl+C is harder to understand than
/// one that clearly waits for a permission.
@MainActor
@Observable
final class EngineController {
    let permissions: PermissionMonitor

    /// The master switch, remembered across launches. The user's choice is
    /// kept while permissions are missing, so the engine comes back by
    /// itself once they are granted.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            update()
        }
    }

    /// Whether the engine is actually running.
    private(set) var isActive = false

    /// While set, the engine stands aside even though it is switched on:
    /// a quick break, for a game or someone else at the keyboard. Not
    /// remembered, so relaunching KeyBridge ends it. `.distantFuture` means
    /// until the user resumes.
    private(set) var pausedUntil: Date?

    var isPaused: Bool { pausedUntil != nil }

    @ObservationIgnored private var resumeTimer: Timer?

    /// The master switch can only be turned on with every permission granted.
    var canEnable: Bool { permissions.allGranted }

    static let enabledKey = "engineEnabled"

    @ObservationIgnored private let tap: EventTapControlling
    @ObservationIgnored private let defaults: UserDefaults

    init(permissions: PermissionMonitor, tap: EventTapControlling, defaults: UserDefaults = .standard) {
        self.permissions = permissions
        self.tap = tap
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        permissions.onChange = { [weak self] _ in self?.update() }
    }

    /// Pauses for `duration`, or until `resume()` when nil.
    func pause(for duration: TimeInterval?) {
        resumeTimer?.invalidate()
        resumeTimer = nil
        if let duration {
            let until = Date.now.addingTimeInterval(duration)
            pausedUntil = until
            let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeIfDue() }
            }
            RunLoop.main.add(timer, forMode: .common)
            resumeTimer = timer
        } else {
            pausedUntil = .distantFuture
        }
        Logger.engine.notice("Paused for \(duration.map { "\(Int($0))s" } ?? "as long as the user wants", privacy: .public)")
        update()
    }

    func resume() {
        guard isPaused else { return }
        resumeTimer?.invalidate()
        resumeTimer = nil
        pausedUntil = nil
        Logger.engine.notice("Resumed")
        update()
    }

    /// Ends a timed pause once its time has come. A Mac asleep through the
    /// end of a pause fires the timer late, which lands here too.
    func resumeIfDue(now: Date = .now) {
        if let pausedUntil, pausedUntil <= now { resume() }
    }

    /// Starts or stops the tap to match the switch, the pause and the
    /// permissions.
    func update() {
        let shouldRun = isEnabled && canEnable && !isPaused
        if shouldRun && !tap.isRunning {
            tap.start()
        } else if !shouldRun && tap.isRunning {
            // Also the path when a permission is revoked while running: the
            // tap stops cleanly, releasing any remapped key still held.
            tap.stop()
        }
        isActive = tap.isRunning
    }
}
