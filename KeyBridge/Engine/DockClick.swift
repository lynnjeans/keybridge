import CoreGraphics
import Foundation

/// Clicking the Dock icon of the app in front minimizes its window, as a
/// taskbar button does on Windows; clicking again brings it back (KB-204).
///
/// Nothing is intercepted. Both halves of the click go on to the Dock, which
/// does nothing for the frontmost app; KeyBridge only watches. A plain press
/// starts a lookup of what lies under the pointer, which the main queue runs
/// straight after the tap callback returns. If the release makes it a click,
/// the window found is minimized a moment later, once the app has handled
/// the reopen event the Dock sends it — handled after the minimize, that
/// event would bring the window straight back. The second click needs no
/// help: the Dock itself restores a minimized window of the frontmost app.
///
/// Generic over what a lookup finds, so tests can use plain values instead of
/// Accessibility elements.
@MainActor
final class DockClick<Target> {
    /// Switched from the Mouse page; on by default.
    var isEnabled = true

    /// Finds the window a click at this point should minimize: the focused
    /// window of the frontmost app when the point is on that app's Dock icon,
    /// otherwise nil. Global coordinates, top-left origin, as events carry.
    private let lookUp: @MainActor (CGPoint) -> Target?
    private let minimize: @MainActor (Target) -> Void
    /// Runs work after a delay on the main queue; tests run it at once.
    private let schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void

    /// How far the pointer may move, in points, and how long the button may
    /// be held, in seconds, for a press to count as a click. More is a drag
    /// to rearrange the Dock, or a long press that opens the icon's menu.
    static var slop: Double { 4 }
    static var maximumDuration: TimeInterval { 0.5 }
    /// Time the app gets to handle the Dock's reopen event first.
    static var delay: TimeInterval { 0.15 }

    private struct Press {
        let id: Int
        let location: CGPoint
        let time: TimeInterval
    }

    private var press: Press?
    private var pressCount = 0
    /// What each press's lookup found, until its release is handled.
    private var targets: [Int: Target] = [:]

    init(
        lookUp: @escaping @MainActor (CGPoint) -> Target?,
        minimize: @escaping @MainActor (Target) -> Void,
        schedule: @escaping @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
        }
    ) {
        self.lookUp = lookUp
        self.minimize = minimize
        self.schedule = schedule
    }

    /// Left button pressed. Modifier clicks keep their Dock meaning (⌥ hides
    /// the others, ⌘ shows the app in Finder), so they are left out.
    /// `time` is seconds on any steady clock, read when the event arrives.
    func mouseDown(at location: CGPoint, flags: CGEventFlags, time: TimeInterval) {
        press = nil
        targets = [:]
        guard isEnabled, flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty else {
            return
        }
        pressCount += 1
        let id = pressCount
        press = Press(id: id, location: location, time: time)
        schedule(0) { [weak self] in
            // Still the latest press, whether or not it has been released.
            guard let self, self.pressCount == id, let target = self.lookUp(location) else { return }
            self.targets[id] = target
        }
    }

    /// Left button released. Scheduled after the press's lookup, so on the
    /// main queue the lookup has run by the time the minimize is decided.
    func mouseUp(at location: CGPoint, time: TimeInterval) {
        guard let press else { return }
        self.press = nil
        let moved = hypot(location.x - press.location.x, location.y - press.location.y)
        let held = time - press.time
        guard moved <= Self.slop, held <= Self.maximumDuration else {
            targets[press.id] = nil
            return
        }
        schedule(Self.delay) { [weak self] in
            guard let self, let target = self.targets.removeValue(forKey: press.id) else { return }
            self.minimize(target)
        }
    }
}
