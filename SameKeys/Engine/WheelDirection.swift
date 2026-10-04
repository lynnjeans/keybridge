import AppKit
import CoreGraphics

/// Which way a mouse wheel scrolls.
enum WheelDirection: String, Codable, CaseIterable, Sendable {
    /// Whatever System Settings says. macOS turns natural scrolling on for
    /// the trackpad and every mouse at once.
    case system
    /// As on Windows: rolling the wheel towards you moves down the page,
    /// whatever the natural scrolling setting, and the trackpad keeps it.
    case windows

    /// Whether a scroll event has to be turned around. Only wheels are:
    /// touch gestures follow the system setting.
    func reverses(source: ScrollSource, isNatural: Bool) -> Bool {
        self == .windows && source != .gesture && isNatural
    }
}

extension CGEvent {
    /// Whether natural scrolling was applied to this event.
    var isNaturalScrolling: Bool {
        NSEvent(cgEvent: self)?.isDirectionInvertedFromDevice ?? false
    }

    /// Turns a scroll event around on both axes, in place. Every form of the
    /// distance is flipped, since apps read different ones: lines, fixed
    /// point lines and pixels.
    func reverseScroll() {
        let lineFields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2]
        let lines = lineFields.map { getIntegerValueField($0) }
        let fixedFields: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
        let fixed = fixedFields.map { getDoubleValueField($0) }
        let pointFields: [CGEventField] = [.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
        let points = pointFields.map { getIntegerValueField($0) }
        // Setting one form can recompute the others, so all are read first
        // and written from the coarsest to the finest.
        for (field, value) in zip(lineFields, lines) { setIntegerValueField(field, value: -value) }
        for (field, value) in zip(fixedFields, fixed) { setDoubleValueField(field, value: -value) }
        for (field, value) in zip(pointFields, points) { setIntegerValueField(field, value: -value) }
    }
}
