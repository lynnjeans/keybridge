import OSLog
import SwiftUI

@main
struct KeyBridgeApp: App {
    init() {
        // Record permission state at launch so it can be read back from the
        // system log when diagnosing a user's setup.
        let permissions = PermissionService()
        for permission in Permission.allCases {
            let status = permissions.status(of: permission)
            Logger.permissions.notice(
                "\(permission.rawValue, privacy: .public): \(status.rawValue, privacy: .public)"
            )
        }
    }

    var body: some Scene {
        // With LSUIElement set there is no Dock icon, so the menu bar item is
        // the app's only permanent presence and the way into everything else.
        MenuBarExtra("KeyBridge", systemImage: "command") {
            MenuBarContent()
        }

        Window("KeyBridge", id: WindowID.main) {
            MainWindow()
        }
        .defaultSize(width: 880, height: 600)
        .windowResizability(.contentMinSize)
    }
}

/// Identifiers for the app's windows, for use with `openWindow(id:)`.
enum WindowID {
    static let main = "main"
}
