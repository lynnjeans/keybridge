import AppKit
import SwiftUI

/// The dropdown shown from the menu bar item: what KeyBridge is doing, the
/// master switch, a quick pause, and the way into the main window.
struct MenuBarContent: View {
    let engine: EngineController
    let onboarding: OnboardingController
    let secureInput: SecureInputMonitor
    @Environment(\.openWindow) private var openWindow

    private var permissions: PermissionMonitor { engine.permissions }

    var body: some View {
        Text(status)

        Toggle("Windows Shortcut Mode", isOn: Binding(
            get: { engine.isEnabled && engine.canEnable },
            set: { engine.isEnabled = $0 }
        ))
        .disabled(!engine.canEnable)

        if engine.isPaused {
            Button("Resume Now") { engine.resume() }
        } else {
            Menu("Pause") {
                Button("For 5 Minutes") { engine.pause(for: 5 * 60) }
                Button("For 15 Minutes") { engine.pause(for: 15 * 60) }
                Button("For 1 Hour") { engine.pause(for: 60 * 60) }
                Divider()
                Button("Until I Resume") { engine.pause(for: nil) }
            }
            .disabled(!engine.isActive)
        }

        // Only when something is missing; the Overview has the full picture.
        if !permissions.allGranted {
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
                Button("Set Up Permissions…") { onboarding.open() }
            }
        }

        Divider()

        Button("Open KeyBridge…") {
            openWindow(id: WindowID.main)
            // A menu bar app is never frontmost on its own, so without this
            // the window opens behind whatever the user was working in.
            NSApplication.shared.activate()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit KeyBridge") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// One line on what KeyBridge is doing right now.
    private var status: String {
        if !engine.canEnable { return "KeyBridge needs permissions" }
        if !engine.isEnabled { return "KeyBridge is off" }
        if let until = engine.pausedUntil {
            return until == .distantFuture
                ? "Paused"
                : "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if engine.isActive, let holder = secureInput.holder {
            return "Keyboard paused by Secure Input" + (holder.appName.map { " (\($0))" } ?? "")
        }
        return engine.isActive ? "KeyBridge is on" : "KeyBridge could not start"
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
