#if DEBUG
import CoreGraphics
import OSLog

/// Debug-only listen-only tap placed after every other session tap, so it sees
/// events the way applications receive them: after KeyBridge's own tap has
/// rewritten them. Used by the remap self-test.
///
/// It reports only F17–F20 and mouse buttons 4 and up, which the self-test
/// uses, so ordinary typing and clicking never reach the log.
@MainActor
enum DownstreamProbe {
    private static var port: CFMachPort?

    static func start() {
        guard port == nil else { return }
        let types: [CGEventType] = [.keyDown, .keyUp, .otherMouseDown, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: probeCallback,
            userInfo: nil
        ) else {
            Logger.engine.error("Could not create the downstream probe")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
    }
}

private let reportedKeys: [KeyCode: String] = [.f17: "F17", .f18: "F18", .f19: "F19", .f20: "F20"]

private func probeCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let modifiers = Modifiers(flags: event.flags).names.joined(separator: "+")
    switch type {
    case .keyDown, .keyUp:
        if let name = reportedKeys[event.keyCode] {
            let phase = type == .keyDown ? (event.isAutorepeat ? "repeat" : "down") : "up"
            Logger.engine.notice("Downstream: \(name, privacy: .public) \(phase, privacy: .public) [\(modifiers, privacy: .public)]")
        }
    case .otherMouseDown, .otherMouseUp:
        let number = event.mouseButtonNumber
        if number >= 4 {
            let phase = type == .otherMouseDown ? "down" : "up"
            Logger.engine.notice("Downstream: button \(number, privacy: .public) \(phase, privacy: .public)")
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
#endif
