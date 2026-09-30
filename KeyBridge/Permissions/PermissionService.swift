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
    private let readInFreshProcess: @Sendable () -> [Permission: PermissionStatus]?

    init(
        isAccessibilityTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        inputMonitoringAccess: @escaping @Sendable () -> IOHIDAccessType = {
            IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        },
        requestInputMonitoring: @escaping @Sendable () -> Bool = {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        },
        readInFreshProcess: @escaping @Sendable () -> [Permission: PermissionStatus]? = {
            PermissionService.statusesFromFreshProcess()
        }
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.inputMonitoringAccess = inputMonitoringAccess
        self.requestInputMonitoring = requestInputMonitoring
        self.readInFreshProcess = readInFreshProcess
    }

    /// Every status as a process started just now sees it, or nil if that
    /// failed. See `statusesFromFreshProcess`.
    func freshStatuses() -> [Permission: PermissionStatus]? {
        readInFreshProcess()
    }

    /// The status as this process sees it. Right at launch that is the truth;
    /// later it can be out of date (see `statusesFromFreshProcess`).
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

    /// The argument that makes KeyBridge print its permissions and exit
    /// (see `Launcher`).
    static let reportArgument = "--report-permissions"

    /// Reads every status in a KeyBridge process started for just that
    /// (KB-236).
    ///
    /// On macOS 26 a running process can be told something out of date.
    /// After the switch in System Settings › Accessibility was turned off,
    /// `AXIsProcessTrusted()` kept answering yes, and KeyBridge kept putting
    /// a tap that could no longer work back in the path of every event,
    /// which froze the Mac. After a switch was turned on, the process kept
    /// hearing no; `CGPreflightPostEventAccess()` went stale the same way.
    /// A process started afterwards always got the true answer. So KeyBridge
    /// runs its own executable with `reportArgument`: it prints the statuses
    /// before the app starts and exits. It shows nothing and never prompts.
    /// Gives up after two seconds.
    static func statusesFromFreshProcess() -> [Permission: PermissionStatus]? {
        // Only KeyBridge itself knows the argument; a test runner does not.
        guard Bundle.main.bundleIdentifier?.hasPrefix("io.github.lynnjeans.KeyBridge") == true,
              let executable = Bundle.main.executableURL else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = [reportArgument]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        guard finished.wait(timeout: .now() + 2) == .success else {
            process.terminate()
            Logger.permissions.error("The permission check in a fresh process did not answer")
            return nil
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return parseReport(text)
    }

    /// What the process started with `reportArgument` prints, one
    /// `permission=status` pair per permission.
    static func report(_ service: PermissionService = PermissionService()) -> String {
        Permission.allCases.map { "\($0.rawValue)=\(service.status(of: $0).rawValue)" }.joined(separator: " ")
    }

    static func parseReport(_ text: String) -> [Permission: PermissionStatus]? {
        var statuses: [Permission: PermissionStatus] = [:]
        for pair in text.split(whereSeparator: \.isWhitespace) {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let permission = Permission(rawValue: parts[0]),
                  let status = PermissionStatus(rawValue: parts[1]) else { return nil }
            statuses[permission] = status
        }
        return statuses.count == Permission.allCases.count ? statuses : nil
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
