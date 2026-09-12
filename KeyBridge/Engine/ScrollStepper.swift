/// Turns wheel scrolling into discrete steps, so that a scroll rule such as
/// page zoom fires once per notch of the wheel.
///
/// A notched wheel sends one event per notch, and each one is a step. A
/// smooth wheel sends a stream of small movements; they are added up, and
/// every line's worth of travel is a step. Without this, a light touch on a
/// smooth wheel would zoom through several levels at once.
struct ScrollStepper {
    /// How far a smooth wheel has to travel, in lines, to make one step.
    static let smoothStepLines = 1.0
    /// A pause this long, in nanoseconds, drops any partial travel, so the
    /// remains of one scroll never complete a step in the next.
    static let idleReset: UInt64 = 300_000_000

    private var travel = 0.0
    private var lastDirection: ScrollDirection?
    private var lastTimestamp: UInt64 = 0

    /// Returns true if this scroll event completes a step.
    mutating func step(
        direction: ScrollDirection, source: ScrollSource, lines: Double, timestamp: UInt64
    ) -> Bool {
        defer {
            lastDirection = direction
            lastTimestamp = timestamp
        }
        if source == .notchedWheel {
            travel = 0
            return true
        }
        let isIdle = timestamp < lastTimestamp || timestamp - lastTimestamp > Self.idleReset
        if direction != lastDirection || isIdle {
            travel = 0
        }
        travel += abs(lines)
        guard travel >= Self.smoothStepLines else { return false }
        travel -= Self.smoothStepLines
        return true
    }
}
