import AppKit
import SwiftUI

/// The dropdown shown from the menu bar item.
struct MenuBarContent: View {
    let permissions: PermissionMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Live permission state. A missing permission opens its System
        // Settings pane when chosen. The fuller status card is KB-006.
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
}
