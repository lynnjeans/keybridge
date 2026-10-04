import Foundation
import Observation
import OSLog

/// A diagnostic recording (KB-247): for a few minutes the user asks for, each
/// shortcut pressed is noted with the keyboard it was taken for, the app in
/// front and what it became, for the next exported report. Never plain
/// typing (`DispatchTrace.isWorthRecording`), and kept in memory only.
@MainActor
@Observable
final class DiagnosticRecorder {
    static let duration: TimeInterval = 5 * 60
    /// More than anyone presses in five minutes; the oldest go first.
    static let lineLimit = 3000

    private(set) var isRecording = false
    private(set) var endsAt: Date?
    /// The last recording, kept after it stops until the next one starts.
    private(set) var lines: [String] = []
    private(set) var startedAt: Date?

    @ObservationIgnored private let attach: @MainActor ((@MainActor (DispatchTrace) -> Void)?) -> Void
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var timer: Timer?

    /// - Parameter attach: hands the dispatcher the function each press is
    ///   described to, or nil to stop.
    init(attach: @escaping @MainActor ((@MainActor (DispatchTrace) -> Void)?) -> Void,
         now: @escaping @MainActor () -> Date = { .now }) {
        self.attach = attach
        self.now = now
    }

    func start(for duration: TimeInterval = DiagnosticRecorder.duration) {
        stop()
        lines = []
        let start = now()
        startedAt = start
        endsAt = start.addingTimeInterval(duration)
        isRecording = true
        attach { [weak self] in self?.add($0) }
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        Logger.diagnostics.notice("Recording started for \(Int(duration), privacy: .public)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard isRecording else { return }
        attach(nil)
        isRecording = false
        endsAt = nil
        Logger.diagnostics.notice("Recording stopped: \(self.lines.count, privacy: .public) presses")
    }

    func add(_ trace: DispatchTrace) {
        lines.append(trace.line(at: now()))
        if lines.count > Self.lineLimit { lines.removeFirst(lines.count - Self.lineLimit) }
    }
}

extension Logger {
    static let diagnostics = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SameKeys", category: "diagnostics")
}
