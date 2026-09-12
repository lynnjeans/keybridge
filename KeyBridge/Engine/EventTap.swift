import CoreGraphics
import Foundation
import OSLog

/// Owns KeyBridge's system-wide event tap: creates it, keeps it attached to the
/// main run loop, keeps it alive, and tears it down.
///
/// The tap is active rather than listen-only, because remapping has to modify
/// and swallow events. Each event is handed to the `Dispatcher`, which decides
/// whether it continues, is removed, or is replaced.
@MainActor
final class EventTap {
    enum Category: String, CaseIterable, Sendable {
        /// Ordinary key presses and releases.
        case keyboard
        /// Modifier state changes (Shift, Control, Option, Command, fn). Kept
        /// apart from `keyboard` because the system can deliver these while
        /// withholding ordinary keys, and the difference matters when
        /// diagnosing permissions.
        case modifier
        case mouseButton
        case scroll
    }

    private let dispatcher: Dispatcher
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    /// How many times the system disabled the tap and it was brought back.
    private(set) var recoveryCount = 0

    var isRunning: Bool { port != nil }

    init(dispatcher: Dispatcher) {
        self.dispatcher = dispatcher
    }

    /// Creates and enables the tap. Returns false if the system refuses, which
    /// is what happens when Accessibility has not been granted.
    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.eventTap.error("Could not create the event tap; is Accessibility granted?")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source

        #if DEBUG
        startCounting()
        armStallIfRequested()
        #endif
        Logger.eventTap.notice("Event tap started")
        return true
    }

    func stop() {
        guard let port else { return }

        CGEvent.tapEnable(tap: port, enable: false)
        dispatcher.releaseHeldKeys()
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        self.port = nil
        self.source = nil

        #if DEBUG
        stopCounting()
        #endif
        Logger.eventTap.notice("Event tap stopped")
    }

    fileprivate func handle(_ event: CGEvent, type: CGEventType) -> Dispatcher.Disposition {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            recover(from: type)
            return .passThrough
        default:
            #if DEBUG
            stallIfArmed()
            if let category = Self.category(of: type) {
                counts[category, default: 0] += 1
            }
            #endif
            return process(event, type: type)
        }
    }

    /// Runs the dispatcher and measures how long it takes. Each call is a
    /// signpost interval, so Instruments can chart processing time in any
    /// build; debug builds also report an average and maximum in the log.
    private func process(_ event: CGEvent, type: CGEventType) -> Dispatcher.Disposition {
        let state = Self.signposter.beginInterval("process")
        #if DEBUG
        let start = DispatchTime.now().uptimeNanoseconds
        #endif

        let disposition = dispatcher.process(event, type: type)

        #if DEBUG
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        processedCount += 1
        processingTotal += elapsed
        processingMax = max(processingMax, elapsed)
        #endif
        Self.signposter.endInterval("process", state)
        return disposition
    }

    /// Called for events KeyBridge posted itself, which are passed through
    /// without any processing.
    fileprivate func handleOwnEvent() {
        #if DEBUG
        ownCount += 1
        #endif
    }

    /// macOS disables a tap whose callback takes too long, and never turns it
    /// back on. Without this the app keeps running but silently stops working.
    private func recover(from type: CGEventType) {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        recoveryCount += 1
        let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
        Logger.eventTap.error(
            "Event tap was disabled by the system (\(reason, privacy: .public)); re-enabled, recovery #\(self.recoveryCount, privacy: .public)"
        )
    }

    private static func category(of type: CGEventType) -> Category? {
        switch type {
        case .keyDown, .keyUp:
            return .keyboard
        case .flagsChanged:
            return .modifier
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp:
            return .mouseButton
        case .scrollWheel:
            return .scroll
        default:
            return nil
        }
    }

    private static let signposter = OSSignposter(logger: .eventTap)

    // Mouse movement is deliberately left out: it is by far the noisiest event
    // stream and nothing KeyBridge does needs it.
    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .scrollWheel,
        ]
        return types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    }()

    #if DEBUG
    // Development aid: how many events of each category arrived, how long
    // processing took, and which rules matched, reported every few seconds.
    // Counts only, never contents — logging keystrokes would turn the system
    // log into a keylogger.
    private var counts: [Category: Int] = [:]
    private var ownCount = 0
    private var processedCount = 0
    private var processingTotal: UInt64 = 0
    private var processingMax: UInt64 = 0
    private var reportTimer: Timer?

    /// Set by launching with KB_DEBUG_STALL_ONCE in the environment: the next
    /// event blocks the callback long enough for macOS to disable the tap, so
    /// recovery can be tested on demand.
    private var stallArmed = false

    private func startCounting() {
        reportTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportCounts() }
        }
    }

    private func stopCounting() {
        reportTimer?.invalidate()
        reportTimer = nil
        counts = [:]
        ownCount = 0
        resetProcessingStats()
    }

    private func resetProcessingStats() {
        processedCount = 0
        processingTotal = 0
        processingMax = 0
    }

    private func reportCounts() {
        let matches = dispatcher.takeMatchCounts()
        guard !counts.isEmpty || ownCount > 0 else { return }

        let summary = (Category.allCases.map { "\($0.rawValue)=\(counts[$0, default: 0])" }
            + ["own=\(ownCount)"])
            .joined(separator: " ")
        Logger.eventTap.notice("Events in the last 3s: \(summary, privacy: .public)")

        if processedCount > 0 {
            let average = Double(processingTotal) / Double(processedCount) / 1000
            let maximum = Double(processingMax) / 1000
            Logger.eventTap.notice(
                "Processing: n=\(self.processedCount, privacy: .public) avg=\(average, format: .fixed(precision: 1), privacy: .public)µs max=\(maximum, format: .fixed(precision: 1), privacy: .public)µs"
            )
        }
        if !matches.isEmpty {
            let list = matches.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            Logger.engine.notice("Matched rules: \(list, privacy: .public)")
        }

        counts = [:]
        ownCount = 0
        resetProcessingStats()
    }

    private func armStallIfRequested() {
        guard ProcessInfo.processInfo.environment["KB_DEBUG_STALL_ONCE"] != nil else { return }
        stallArmed = true
        Logger.eventTap.notice("Stall armed: the next event will block the tap")
    }

    private func stallIfArmed() {
        guard stallArmed else { return }
        stallArmed = false
        Logger.eventTap.notice("Simulating a stalled callback")
        Thread.sleep(forTimeInterval: 2)
    }
    #endif
}

/// C callback for the tap. Must not capture context, so the owning EventTap is
/// recovered from `userInfo`.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

    // Events KeyBridge posted itself pass straight through: rewriting them
    // again could loop forever. The tap-disabled notices carry no real event,
    // so they skip this check and go on to be handled.
    let isDisabledNotice = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    if !isDisabledNotice && SyntheticEvent.isOurs(event) {
        MainActor.assumeIsolated { tap.handleOwnEvent() }
        return Unmanaged.passUnretained(event)
    }

    // The run loop source is on the main run loop, so this is the main thread,
    // and the event never leaves it.
    nonisolated(unsafe) let event = event
    switch MainActor.assumeIsolated({ tap.handle(event, type: type) }) {
    case .passThrough:
        return Unmanaged.passUnretained(event)
    case .consume:
        return nil
    case .replace(let replacement):
        // The system releases a replacement event once it has taken it over,
        // so it is handed over with a retain of its own.
        return Unmanaged.passRetained(replacement)
    }
}

extension Logger {
    static let eventTap = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge",
        category: "eventtap"
    )
}
