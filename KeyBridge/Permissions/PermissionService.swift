import ApplicationServices
import IOKit.hid
import OSLog

/// The system permissions KeyBridge needs in order to intercept and rewrite input.
enum Permission: String, CaseIterable, Sendable {
    /// Needed to modify events in flight and to post synthesized ones.
    case accessibility
    /// Needed to observe keyboard, mouse and scroll events at all.
    case inputMonitoring
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

    init(
        isAccessibilityTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        inputMonitoringAccess: @escaping @Sendable () -> IOHIDAccessType = {
            IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        }
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.inputMonitoringAccess = inputMonitoringAccess
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
