import Foundation
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

    /// Starts or stops the tap to match the switch and the permissions.
    func update() {
        let shouldRun = isEnabled && canEnable
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
