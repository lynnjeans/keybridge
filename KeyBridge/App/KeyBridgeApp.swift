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
                secureInput: appDelegate.secureInput
            )
        }
        .defaultSize(width: 880, height: 600)
        .windowResizability(.contentMinSize)

        // The first-run guide, sized by its content.
        Window("Set Up KeyBridge", id: WindowID.onboarding) {
            OnboardingWindow(onboarding: appDelegate.onboarding)
        }
        .windowResizability(.contentSize)
    }
}

/// Identifiers for the app's windows, for use with `openWindow(id:)`.
enum WindowID {
    static let main = "main"
    static let onboarding = "onboarding"
}
