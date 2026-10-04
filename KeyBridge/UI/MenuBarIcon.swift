import AppKit
import SwiftUI

/// The menu bar item's icon: the app icon's arch bridge, faded while the
/// engine is not running, so a missing permission or a switched-off
/// KeyBridge is visible without opening anything. A dot in its corner means a new version is
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
        let symbol = Self.bridge()
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
        image.accessibilityDescription = "KeyBridge"
        return image
    }

    /// The arch bridge of the app icon (`AppIcon.icon/Assets/bridge.svg`),
    /// cut for the menu bar (KB-251): narrower than the original, which is
    /// three and a half times as wide as it is tall, with three hangers
    /// instead of five and heavier lines, so it stays clear at 16 points.
    /// Drawn here rather than taken from SF Symbols, so it is KeyBridge's own.
    private static func bridge() -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let deckY: CGFloat = 3.5, rise: CGFloat = 9.5
        return NSImage(size: size, flipped: false) { _ in
            NSColor.black.set()
            let deckInset: CGFloat = 1.2
            let x0 = deckInset + size.width * 0.055, x1 = size.width - x0, span = x1 - x0
            // As in the icon: the control points sit 15.5% of the span in
            // from each end, and the arch peaks at three quarters of their height.
            let start = CGPoint(x: x0, y: deckY), end = CGPoint(x: x1, y: deckY)
            let control1 = CGPoint(x: x0 + span * 0.155, y: deckY + rise / 0.75)
            let control2 = CGPoint(x: x1 - span * 0.155, y: deckY + rise / 0.75)
            let arch = NSBezierPath()
            arch.move(to: start)
            arch.curve(to: end, controlPoint1: control1, controlPoint2: control2)
            arch.lineWidth = 1.8
            arch.lineCapStyle = .round
            arch.stroke()

            let deck = NSBezierPath()
            deck.move(to: CGPoint(x: deckInset, y: deckY))
            deck.line(to: CGPoint(x: size.width - deckInset, y: deckY))
            deck.lineWidth = 1.8
            deck.lineCapStyle = .round
            deck.stroke()

            // Hangers from the deck up to the arch. The curve is symmetric
            // and its x grows with t, so each top is found by bisection.
            func point(_ t: CGFloat) -> CGPoint {
                let u = 1 - t
                let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                return CGPoint(x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                               y: a * start.y + b * control1.y + c * control2.y + d * end.y)
            }
            for fraction: CGFloat in [0.28, 0.5, 0.72] {
                let x = x0 + span * fraction
                var low: CGFloat = 0, high: CGFloat = 1
                for _ in 0..<20 {
                    let middle = (low + high) / 2
                    if point(middle).x < x { low = middle } else { high = middle }
                }
                let hanger = NSBezierPath()
                hanger.move(to: CGPoint(x: x, y: deckY))
                hanger.line(to: CGPoint(x: x, y: point(low).y))
                hanger.lineWidth = 1.3
                hanger.stroke()
            }
            return true
        }
    }
}
