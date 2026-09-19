import AppKit
import SwiftUI

/// The menu bar item's icon: the ⌘ symbol, faded while the engine is not
/// running, so a missing permission or a switched-off KeyBridge is visible
/// without opening anything.
///
/// As the one view that lives as long as the app, it also opens the main
/// window and the first-run guide when asked through `.openMainWindow` and
/// `.openOnboarding`.
struct MenuBarIcon: View {
    let isActive: Bool
    let onboarding: OnboardingController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: isActive ? Self.active : Self.muted)
            // The first thing the app puts on screen, and the earliest point
            // at which a window can be opened: `applicationDidFinishLaunching`
            // runs before SwiftUI has installed any of this.
            .onAppear {
                if onboarding.shouldOpenAtLaunch() { open(WindowID.onboarding) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                open(WindowID.main)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openOnboarding)) { _ in
                open(WindowID.onboarding)
            }
    }

    private func open(_ id: String) {
        openWindow(id: id)
        WindowID.bringToFront(id)
    }

    // Menu bar icons are template images: macOS colors them to match the menu
    // bar and uses only their alpha, so fading means drawing at lower alpha.
    @MainActor private static let active: NSImage = {
        let image = symbol()
        image.isTemplate = true
        return image
    }()

    @MainActor private static let muted: NSImage = {
        let symbol = Self.symbol()
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.35)
            return true
        }
        image.isTemplate = true
        return image
    }()

    private static func symbol() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return NSImage(systemSymbolName: "command", accessibilityDescription: "KeyBridge")!
            .withSymbolConfiguration(configuration)!
    }
}
