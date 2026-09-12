import SwiftUI

@main
struct KeyBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // With LSUIElement set there is no Dock icon, so the menu bar item is
        // the app's only permanent presence and the way into everything else.
        MenuBarExtra {
            MenuBarContent(permissions: appDelegate.permissionMonitor)
        } label: {
            MenuBarIcon(isActive: appDelegate.engine.isActive)
        }

        Window("KeyBridge", id: WindowID.main) {
            MainWindow(engine: appDelegate.engine)
        }
        .defaultSize(width: 880, height: 600)
        .windowResizability(.contentMinSize)
    }
}

/// Identifiers for the app's windows, for use with `openWindow(id:)`.
enum WindowID {
    static let main = "main"
}
