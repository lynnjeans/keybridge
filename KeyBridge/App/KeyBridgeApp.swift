import SwiftUI

@main
struct KeyBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // With LSUIElement set there is no Dock icon, so the menu bar item is
        // the app's only permanent presence and the way into everything else.
        MenuBarExtra {
            MenuBarContent(engine: appDelegate.engine, onboarding: appDelegate.onboarding, secureInput: appDelegate.secureInput)
        } label: {
            MenuBarIcon(isActive: appDelegate.engine.isActive && appDelegate.secureInput.holder == nil, onboarding: appDelegate.onboarding)
        }

        Window("KeyBridge", id: WindowID.main) {
            MainWindow(
                engine: appDelegate.engine,
                onboarding: appDelegate.onboarding,
                rules: appDelegate.rules,
                secureInput: appDelegate.secureInput,
                otherRemappers: appDelegate.otherRemappers,
                clipboard: appDelegate.clipboard,
                pathBox: appDelegate.pathBox,
                quickSwitch: appDelegate.quickSwitch
            )
        }
        .defaultSize(width: 880, height: 600)
        .windowResizability(.contentMinSize)
        // A keybridge:// URL from the Finder extension would otherwise open
        // this window; AppDelegate handles those URLs itself.
        .handlesExternalEvents(matching: [])

        // The first-run guide, sized by its content.
        Window("Set Up KeyBridge", id: WindowID.onboarding) {
            OnboardingWindow(onboarding: appDelegate.onboarding)
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])
    }
}

/// Identifiers for the app's windows, for use with `openWindow(id:)`.
enum WindowID {
    static let main = "main"
    static let onboarding = "onboarding"

    /// Brings a window that was just opened in front of the app the user is
    /// working in.
    ///
    /// `activate()` alone is only a request since macOS 14, and it is often
    /// refused when the click came through the menu bar item, which macOS 26
    /// hosts in Control Center rather than in KeyBridge: the window then
    /// opened behind the frontmost app's. Ordering the window itself to the
    /// front is not refused.
    @MainActor
    static func bringToFront(_ id: String) {
        NSApplication.shared.activate()
        // On a first open, SwiftUI creates the window after this returns.
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows where window.identifier?.rawValue.hasPrefix(id) == true {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}
