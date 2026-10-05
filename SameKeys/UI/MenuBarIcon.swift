import AppKit
import SwiftUI

/// The menu bar item's icon: the ∞ of the app icon (SK-273), faded while the
/// engine is not running, so a missing permission or a switched-off
/// SameKeys is visible without opening anything. A dot in its corner means a new version is
/// waiting (KB-101).
///
/// As the one view that lives as long as the app, it also opens the main
/// window and the first-run guide when asked through `.openMainWindow` and
/// `.openOnboarding`.
struct MenuBarIcon: View {
    let isActive: Bool
    var hasUpdate = false
    let onboarding: OnboardingController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: Self.images[isActive ? 1 : 0][hasUpdate ? 1 : 0])
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
    // bar and uses only their alpha, so fading means drawing at lower alpha,
    // and the dot is drawn in the same color with a clear ring around it.
    // Indexed [active][has update].
    @MainActor private static let images: [[NSImage]] = [false, true].map { active in
        [false, true].map { badge in image(fraction: active ? 1 : 0.35, badge: badge) }
    }

    private static func image(fraction: CGFloat, badge: Bool) -> NSImage {
        let symbol = Self.infinity()
        // Room on the right for the dot, so the symbol keeps its size.
        let size = NSSize(width: symbol.size.width + (badge ? 4 : 0), height: symbol.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            symbol.draw(in: NSRect(origin: .zero, size: symbol.size), from: .zero, operation: .sourceOver, fraction: fraction)
            if badge {
                let dot = NSRect(x: size.width - 7, y: size.height - 7, width: 7, height: 7)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SameKeys"
        return image
    }

    /// The ∞ joining C and ⌘, from the user's own drawing (SK-273), as
    /// written by `scripts/icons/infinity.py`: 32 by 16 points, black on
    /// clear, read as a template so macOS colors it for the menu bar.
    private static func infinity() -> NSImage {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 32, height: 16)
            return image
        }
        // Not expected: the file ships in the app. A plain keyboard keeps the
        // item visible rather than leaving an empty slot.
        return NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) ?? NSImage()
    }
}
