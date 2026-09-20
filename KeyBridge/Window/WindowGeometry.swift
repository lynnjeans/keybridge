import CoreGraphics

/// The geometry behind window snapping (KB-200): which screen a window is on,
/// and how the two coordinate systems macOS uses line up.
///
/// AppKit places screens and windows with the origin at the bottom-left of the
/// primary display and y growing upwards. The Accessibility API, which is how
/// KeyBridge moves other apps' windows, uses the top-left of the primary
/// display with y growing downwards — the same convention as the event tap.
/// Everything here works in Accessibility coordinates; `WindowElement` flips
/// what it reads from `NSScreen` once, on the way in.
///
/// Pure arithmetic on plain values, so the rules can be tested without a
/// second display and without moving anyone's windows.
enum WindowGeometry {
    /// A display, in Accessibility coordinates. `visibleFrame` leaves out the
    /// menu bar and the Dock, and is what a snapped window should fill.
    struct Screen: Equatable, Sendable {
        var frame: CGRect
        var visibleFrame: CGRect

        init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// Turns an AppKit rectangle (bottom-left origin, y up) into an
    /// Accessibility one (top-left origin, y down), and back: the conversion
    /// is its own inverse.
    ///
    /// `primaryHeight` is the height of the primary display — `NSScreen`'s
    /// first screen, whose frame starts at the origin in both systems.
    static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// The screen a window belongs to: the one its frame overlaps most, as
    /// macOS itself decides when a window straddles two displays. A window
    /// that overlaps none — dragged into a gap between mismatched displays,
    /// or left behind by a display that was unplugged — goes to the screen
    /// whose centre is nearest, so it can still be snapped somewhere.
    ///
    /// Nil only when there are no screens at all.
    static func screen(for frame: CGRect, among screens: [Screen]) -> Screen? {
        guard !screens.isEmpty else { return nil }
        let overlapping = screens
            .map { (screen: $0, area: area(of: $0.frame.intersection(frame))) }
            .filter { $0.area > 0 }
        if let best = overlapping.max(by: { $0.area < $1.area }) { return best.screen }
        return screens.min { distance(frame, $0.frame) < distance(frame, $1.frame) }
    }

    /// Keeps a frame inside a screen's usable area: shrunk to fit if it is
    /// larger, then nudged back in if it hangs over an edge. Moving a window
    /// to another display uses this, and so will the snap shortcuts, so a
    /// window can never land under the menu bar or off the side where it
    /// cannot be dragged back.
    static func fit(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Zero for an empty or null rectangle, which `CGRect.intersection`
    /// returns when two frames do not meet.
    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.midX - b.midX
        let dy = a.midY - b.midY
        return dx * dx + dy * dy
    }
}
