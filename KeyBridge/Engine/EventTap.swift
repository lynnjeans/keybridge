import CoreGraphics
import Foundation
import OSLog

/// Owns KeyBridge's system-wide event tap: creates it, keeps it attached to the
/// main run loop, and tears it down.
///
/// The tap is active rather than listen-only, because remapping has to modify
/// and swallow events. For now every event is passed through untouched;
/// matching and rewriting arrive with the dispatch pipeline.
@MainActor
final class EventTap {
    enum Category: String, CaseIterable, Sendable {
        case keyboard
        case mouseButton
        case scroll
    }

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { port != nil }

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
        #endif
        Logger.eventTap.notice("Event tap started")
        return true
    }

    func stop() {
        guard let port else { return }

        CGEvent.tapEnable(tap: port, enable: false)
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

    fileprivate func handle(_ type: CGEventType) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Logger.eventTap.error("Event tap was disabled by the system (type \(type.rawValue, privacy: .public))")
        default:
            #if DEBUG
            if let category = Self.category(of: type) {
                counts[category, default: 0] += 1
            }
            #endif
        }
    }

    private static func category(of type: CGEventType) -> Category? {
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            return .keyboard
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp:
            return .mouseButton
        case .scrollWheel:
            return .scroll
        default:
            return nil
        }
    }

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
    // Development aid: how many events of each category arrived, reported every
    // few seconds. Counts only, never contents — logging keystrokes would turn
    // the system log into a keylogger.
    private var counts: [Category: Int] = [:]
    private var reportTimer: Timer?

    private func startCounting() {
        reportTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportCounts() }
        }
    }

    private func stopCounting() {
        reportTimer?.invalidate()
        reportTimer = nil
        counts = [:]
    }

    private func reportCounts() {
        guard !counts.isEmpty else { return }
        let summary = Category.allCases
            .map { "\($0.rawValue)=\(counts[$0, default: 0])" }
            .joined(separator: " ")
        Logger.eventTap.notice("Events in the last 3s: \(summary, privacy: .public)")
        counts = [:]
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
    if let userInfo {
        let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
        // The run loop source is on the main run loop, so this is the main thread.
        MainActor.assumeIsolated { tap.handle(type) }
    }
    return Unmanaged.passUnretained(event)
}

extension Logger {
    static let eventTap = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge",
        category: "eventtap"
    )
}
