import Foundation

/// Decides whether an event tap the system has disabled may be turned back on
/// (KB-236).
///
/// macOS disables a tap whose callback does not answer in time, and while it
/// waits, every key press and click on the Mac waits with it. Bringing the tap
/// back is right after a one-off stall, but a tap that keeps timing out, as one
/// whose Accessibility permission was revoked does, would freeze all input if
/// it were brought back forever. So a few disables close together trip the
/// breaker, and the tap stays off.
struct TapBreaker {
    /// Disables within `window` that trip the breaker.
    var limit = 3
    var window: TimeInterval = 30

    private var disables: [TimeInterval] = []

    /// Records that the tap was disabled at `time` (seconds, any monotonic
    /// clock) and says whether turning it back on is still allowed.
    mutating func recordDisable(at time: TimeInterval) -> Bool {
        disables = disables.filter { time - $0 < window } + [time]
        return disables.count < limit
    }

    mutating func reset() {
        disables = []
    }
}
