import AppKit
import Observation
import OSLog

/// Drives the first-run guide that walks the user through granting the two
/// permissions KeyBridge cannot work without.
///
/// The guide is three steps: Accessibility, Input Monitoring, and a closing
/// step once both are granted. Which one is showing is derived from the live
/// permission state rather than stored, so the flow advances by itself as
/// soon as `PermissionMonitor` sees a grant — the user never comes back from
/// System Settings to a stale window and a Continue button. Revoking a
/// permission steps back to it for the same reason.
@MainActor
@Observable
final class OnboardingController {
    /// A step of the guide. The order is the order they are asked for.
    enum Step: Int, CaseIterable, Sendable {
        case accessibility
        case inputMonitoring
        case ready

        /// The permission this step asks for; `nil` on the closing step.
        var permission: Permission? {
            switch self {
            case .accessibility: .accessibility
            case .inputMonitoring: .inputMonitoring
            case .ready: nil
            }
        }

        /// The step's position, counting from 1, as shown to the user.
        var number: Int { rawValue + 1 }
    }

    /// Remembers that the guide is done, so it only appears on a first run.
    static let completedKey = "onboardingCompleted"

    static let stepCount = Step.allCases.count

    let permissions: PermissionMonitor

    /// The step the user is on: the first permission still missing, or the
    /// closing step when there is none.
    var step: Step {
        for step in Step.allCases {
            guard let permission = step.permission else { break }
            if permissions.status(of: permission) != .granted { return step }
        }
        return .ready
    }

    var hasCompleted: Bool { defaults.bool(forKey: Self.completedKey) }

    /// The launch decision is made once per run: the menu bar item asks on
    /// appearing, and it must not bring the guide back if it appears again
    /// after the user has put it aside.
    @ObservationIgnored private var hasConsideredLaunch = false

    /// Input Monitoring is requested on its own at most once per run: if the
    /// system answers with an alert rather than a silent grant, it should not
    /// come back every time the step is shown.
    @ObservationIgnored private var hasRequestedInputMonitoring = false

    @ObservationIgnored private let service: PermissionService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    @ObservationIgnored private let presentGuide: @MainActor () -> Void

    init(
        permissions: PermissionMonitor,
        service: PermissionService = PermissionService(),
        defaults: UserDefaults = .standard,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        presentGuide: @escaping @MainActor () -> Void = {
            NotificationCenter.default.post(name: .openOnboarding, object: nil)
        }
    ) {
        self.permissions = permissions
        self.service = service
        self.defaults = defaults
        self.openURL = openURL
        self.presentGuide = presentGuide
    }

    /// Whether the guide should come up at launch: a first run that still
    /// needs something. A first run with both permissions already granted —
    /// a reinstall, or a rebuild of an app the user has already trusted —
    /// has nothing to guide, so it is quietly marked done instead.
    ///
    /// The caller opens the window itself rather than going through
    /// `open()`, because at launch there is not yet a view listening for the
    /// notification.
    func shouldOpenAtLaunch() -> Bool {
        guard !hasConsideredLaunch else { return false }
        hasConsideredLaunch = true
        guard !hasCompleted else { return false }
        guard step != .ready else {
            Logger.permissions.notice("Onboarding skipped: every permission is already granted")
            complete()
            return false
        }
        Logger.permissions.notice("First run: opening the permission guide")
        return true
    }

    /// Opens the guide. Also the way back in from the menu bar and the
    /// Overview once the first run is over.
    func open() {
        presentGuide()
    }

    /// Makes sure KeyBridge is in the current step's System Settings list and
    /// opens the pane where it is granted. The deep link is what the user
    /// sees; `PermissionService.request(_:)` only adds the row where needed.
    func openSettings() {
        guard let permission = step.permission else { return }
        service.request(permission)
        Logger.permissions.notice("Onboarding opened settings for \(permission.rawValue, privacy: .public)")
        openURL(permission.settingsURL)
    }

    /// Requests Input Monitoring as soon as the guide reaches that step,
    /// without waiting for the button.
    ///
    /// Once Accessibility is granted, macOS typically approves the request
    /// silently — no alert, often no row in System Settings — so the step
    /// completes by itself. Where it asks instead, the alert appears while
    /// the guide is on the matching step. Nothing is opened: the pane is
    /// still one click away for when the request does not settle it.
    ///
    /// Only a status that has never been decided is requested; for `denied`
    /// the system would do nothing.
    func requestInputMonitoringIfNeeded() {
        guard step == .inputMonitoring,
              permissions.status(of: .inputMonitoring) == .notDetermined,
              !hasRequestedInputMonitoring
        else { return }
        hasRequestedInputMonitoring = true
        service.request(.inputMonitoring)
        Logger.permissions.notice("Onboarding requested inputMonitoring on reaching its step")
        // A silent grant is already in place; show it now rather than on the
        // next poll.
        permissions.refresh()
    }

    /// Marks the guide done so it does not come back on the next launch.
    func complete() {
        defaults.set(true, forKey: Self.completedKey)
    }
}

extension Notification.Name {
    /// Asks the SwiftUI side to open the first-run guide, which only a view
    /// can do.
    static let openOnboarding = Notification.Name("KeyBridgeOpenOnboarding")
}
