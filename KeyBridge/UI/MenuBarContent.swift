import AppKit
import SwiftUI

/// The dropdown shown from the menu bar item: what KeyBridge is doing, the
/// master switch, a quick pause, and the way into the main window.
struct MenuBarContent: View {
    let engine: EngineController
    let onboarding: OnboardingController
    let secureInput: SecureInputMonitor
    let updates: UpdateController
    @Environment(\.openWindow) private var openWindow

    private var permissions: PermissionMonitor { engine.permissions }

    /// In the accent colour: a menu keeps a non-template image's colours.
    private static var updateIcon: Image {
        let symbol = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(paletteColors: [.white, .controlAccentColor]))!
        symbol.isTemplate = false
        return Image(nsImage: symbol)
    }

    var body: some View {
        // Where a scheduled check leaves a new version, next to the dot on
        // the icon, instead of opening a window on its own (KB-101).
        if let pending = updates.pending {
            // An icon and a "New" badge, since a menu item's text cannot be
            // coloured or made bold.
            Group {
                if pending.isDownloaded {
                    Button { updates.installNow() } label: {
                        Label { Text("Restart to Install KeyBridge \(pending.version)") } icon: { Self.updateIcon }
                    }
                } else {
                    Button { updates.checkForUpdates() } label: {
                        Label { Text("KeyBridge \(pending.version) Is Available…") } icon: { Self.updateIcon }
                    }
                }
            }
            // Its own key: plain "New" is Finder's New menu, 新建 in Chinese.
            .badge(Text(String(localized: "update.badge", defaultValue: "New",
                               comment: "Badge on the menu item for a new KeyBridge version")))
            Divider()
        }

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
            WindowID.bringToFront(WindowID.main)
        }
        .keyboardShortcut(",")

        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.canCheckForUpdates)

        Divider()

        Button("Quit KeyBridge") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// One line on what KeyBridge is doing right now.
    private var status: String {
        if !engine.canEnable { return String(localized: "KeyBridge needs permissions") }
        if !engine.isEnabled { return String(localized: "KeyBridge is off") }
        if let until = engine.pausedUntil {
            return until == .distantFuture
                ? String(localized: "Paused")
                : String(localized: "Paused until \(until.formatted(date: .omitted, time: .shortened))")
        }
        if engine.isActive, let holder = secureInput.holder {
            return holder.appName.map { String(localized: "Keyboard paused by Secure Input (\($0))") }
                ?? String(localized: "Keyboard paused by Secure Input")
        }
        return engine.isActive ? String(localized: "KeyBridge is on") : String(localized: "KeyBridge could not start")
    }

}

extension Permission {
    /// The name System Settings uses for the permission.
    var title: String {
        switch self {
        case .accessibility: String(localized: "Accessibility")
        case .inputMonitoring: String(localized: "Input Monitoring")
        }
    }

    /// Why KeyBridge needs it, in the user's terms.
    var purpose: String {
        switch self {
        case .accessibility: String(localized: "Lets KeyBridge replace shortcuts, clicks and scrolling with their Mac equivalents.")
        case .inputMonitoring: String(localized: "Lets KeyBridge see ordinary key presses, such as the C in Ctrl+C.")
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
                ? String(localized: "macOS grants this together with Accessibility and may not list KeyBridge under Input Monitoring.")
                : String(localized: "If KeyBridge is not in the Input Monitoring list, click + and choose KeyBridge.")
        }
    }
}
