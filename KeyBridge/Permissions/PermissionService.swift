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
    private let promptForAccessibility: @Sendable () -> Void
    private let requestInputMonitoring: @Sendable () -> Bool

    init(
        isAccessibilityTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        inputMonitoringAccess: @escaping @Sendable () -> IOHIDAccessType = {
            IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        },
        promptForAccessibility: @escaping @Sendable () -> Void = {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        },
        requestInputMonitoring: @escaping @Sendable () -> Bool = {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.inputMonitoringAccess = inputMonitoringAccess
        self.promptForAccessibility = promptForAccessibility
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

    /// Asks the system for a permission.
    ///
    /// This is what puts KeyBridge into the System Settings list in the first
    /// place: until an app has asked, its row is not there for the user to
    /// switch on. Neither call grants anything by itself — Accessibility only
    /// shows the system's "open Settings" alert, and Input Monitoring shows
    /// its own alert once and afterwards does nothing — so the onboarding
    /// flow always sends the user to the pane as well.
    func request(_ permission: Permission) {
        switch permission {
        case .accessibility: promptForAccessibility()
        case .inputMonitoring: _ = requestInputMonitoring()
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
