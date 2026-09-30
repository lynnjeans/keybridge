import ApplicationServices
import Foundation
import IOKit.hid
import OSLog

/// The system permissions KeyBridge needs in order to intercept and rewrite input.
enum Permission: String, CaseIterable, Sendable {
    /// Needed to modify events in flight and to post synthesized ones.
    case accessibility
    /// Needed to receive ordinary key presses. Without it the system still
    /// delivers modifier changes, mouse buttons and scrolling to an active
    /// tap but silently withholds plain keys, so a Ctrl+C remap would see
    /// the Ctrl and never the C.
    case inputMonitoring
}

extension Permission {
    /// The System Settings pane where the user grants this permission.
    var settingsURL: URL {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

enum PermissionStatus: String, Sendable {
    case granted
    case denied
    /// The user has never been asked. Only Input Monitoring can report this;
    /// Accessibility cannot tell "never asked" apart from "refused".
    case notDetermined
}

/// Reads the current state of the permissions KeyBridge depends on.
///
/// Every query hits the live system state and nothing is cached, so callers
/// can ask as often as they need to. The system checks are injectable so the
/// logic can be tested without touching real privacy settings.
struct PermissionService: Sendable {
    private let isAccessibilityTrusted: @Sendable () -> Bool
    private let inputMonitoringAccess: @Sendable () -> IOHIDAccessType
    private let requestInputMonitoring: @Sendable () -> Bool

    init(
        isAccessibilityTrusted: @escaping @Sendable () -> Bool = {
            // Called for its side effect: it adds KeyBridge's row to the
            // Settings list. Its answer is not trusted (see canCreateActiveTap).
            _ = AXIsProcessTrusted()
            return PermissionService.canCreateActiveTap()
        },
        inputMonitoringAccess: @escaping @Sendable () -> IOHIDAccessType = {
            IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        },
        requestInputMonitoring: @escaping @Sendable () -> Bool = {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.inputMonitoringAccess = inputMonitoringAccess
        self.requestInputMonitoring = requestInputMonitoring
    }

    func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return isAccessibilityTrusted() ? .granted : .denied
        case .inputMonitoring:
            switch inputMonitoringAccess() {
            case kIOHIDAccessTypeGranted: return .granted
            case kIOHIDAccessTypeDenied: return .denied
            default: return .notDetermined
            }
        }
    }

    /// Makes sure KeyBridge has a row in the permission's System Settings
    /// list, so the user has something to switch on. Grants nothing itself;
    /// the onboarding flow sends the user to the pane as well.
    ///
    /// Accessibility needs nothing here: the plain `AXIsProcessTrusted()`
    /// call in every status check already adds the row. Its prompting variant is
    /// deliberately not used — its alert opens on top of the pane the guide
    /// has just opened, and lingers behind System Settings afterwards.
    /// Input Monitoring is different: checking does not add the row, only
    /// requesting does.
    func request(_ permission: Permission) {
        switch permission {
        case .accessibility: break
        case .inputMonitoring: _ = requestInputMonitoring()
        }
    }

    /// Whether Accessibility is granted right now, judged by what it is
    /// needed for: creating an active event tap (KB-236).
    ///
    /// `AXIsProcessTrusted()` goes stale in a running process on macOS 26:
    /// after the switch in System Settings was turned off it kept answering
    /// yes, and KeyBridge kept putting a tap that could no longer work back
    /// in the path of every event, freezing the Mac; after it was turned on
    /// it kept answering no. Whether the system lets a tap be created is
    /// decided at the moment it is asked. The probe listens only for null
    /// events, is never added to a run loop, and is thrown away at once.
    static func canCreateActiveTap() -> Bool {
        guard let probe = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.null.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(probe)
        return true
    }

    /// Whether every permission KeyBridge needs has been granted.
    var allGranted: Bool {
        Permission.allCases.allSatisfy { status(of: $0) == .granted }
    }
}

extension Logger {
    static let permissions = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge",
        category: "permissions"
    )
}
