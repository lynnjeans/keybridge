import AppKit
import SwiftUI

/// The dropdown shown from the menu bar item.
struct MenuBarContent: View {
    let permissions: PermissionMonitor
    let onboarding: OnboardingController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Live permission state. A missing permission opens its System
        // Settings pane when chosen. The Overview has the fuller picture.
        Section("Permissions") {
            ForEach(Permission.allCases, id: \.self) { permission in
                let granted = permissions.status(of: permission) == .granted
                Button {
                    if !granted { NSWorkspace.shared.open(permission.settingsURL) }
                } label: {
                    Label(
                        granted ? "\(permission.title): Granted" : "\(permission.title): Not granted — Open Settings…",
                        systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                }
            }
        }

        if !permissions.allGranted {
            Button("Set Up Permissions…") { onboarding.open() }
        }

        Divider()

        Button("Open KeyBridge…") {
            openWindow(id: WindowID.main)
            // A menu bar app is never frontmost on its own, so without this
            // the window opens behind whatever the user was working in.
            NSApplication.shared.activate()
        }

        Divider()

        Button("Quit KeyBridge") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

extension Permission {
    /// The name System Settings uses for the permission.
    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    /// Why KeyBridge needs it, in the user's terms.
    var purpose: String {
        switch self {
        case .accessibility: "Lets KeyBridge replace shortcuts, clicks and scrolling with their Mac equivalents."
        case .inputMonitoring: "Lets KeyBridge see ordinary key presses, such as the C in Ctrl+C."
        }
    }

    /// What to expect in System Settings, where the pane may not show
    /// KeyBridge at all: once Accessibility is granted, macOS allows Input
    /// Monitoring without storing a decision, so there is no row.
    func settingsHint(granted: Bool) -> String? {
        switch self {
        case .accessibility:
            nil
        case .inputMonitoring:
            granted
                ? "macOS grants this together with Accessibility and may not list KeyBridge under Input Monitoring."
                : "If KeyBridge is not in the Input Monitoring list, click + and choose KeyBridge."
        }
    }
}
