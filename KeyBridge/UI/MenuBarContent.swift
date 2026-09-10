import AppKit
import SwiftUI

/// The dropdown shown from the menu bar item.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
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
