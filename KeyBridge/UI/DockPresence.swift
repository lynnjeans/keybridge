import AppKit
import SwiftUI

/// Gives KeyBridge a Dock icon while one of its windows is open.
///
/// KeyBridge is a menu bar app, without a Dock icon or a place in ⌘Tab. That
/// suits it while it runs in the background, but a settings window that
/// falls behind another app could then only be brought back through the menu
/// bar. While a window is open the app counts as a regular one; when the
/// last window closes it goes back to the menu bar.
@MainActor
enum DockPresence {
    private static var openWindows = 0

    static func windowOpened() {
        openWindows += 1
        if openWindows == 1 {
            NSApplication.shared.setActivationPolicy(.regular)
        }
    }

    static func windowClosed() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

extension View {
    /// Keeps a Dock icon while this window is open.
    func showsInDock() -> some View {
        onAppear(perform: DockPresence.windowOpened)
            .onDisappear(perform: DockPresence.windowClosed)
    }
}
