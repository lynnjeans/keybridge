import Foundation
import OSLog

/// KeyBridge's own log, kept across launches (KB-247). An app can read only
/// the log of its current process, and people often restart before they
/// export a report, so each launch copies its entries into a file of its own
/// in the support folder. The report then carries the earlier launches too.
///
/// Files older than three days go, and the oldest go first once all of them
/// pass 5 MB. Only what KeyBridge logs is kept, as the report has it.
final class LogArchive: @unchecked Sendable {
    static let maxAge: TimeInterval = 3 * 24 * 60 * 60
    static let maxBytes = 5 * 1024 * 1024

    let folder: URL
    /// This launch's file.
    let currentFile: URL
    private let lock = NSLock()
    /// The newest entry copied so far.
    private var copiedUntil: Date?
    private var isFull = false

    init(folder: URL = URL.keyBridgeSupport.appending(path: "Logs"), launch: Date = .now) {
        self.folder = folder
        currentFile = folder.appending(path: "KeyBridge \(Self.fileStamp(launch)).log")
    }

    /// Makes the folder and drops what is too old or too much. Run once at
    /// launch, before anything is written.
    func prune(now: Date = .now) {
        lock.withLock {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var files = earlierFiles()
            for file in files where now.timeIntervalSince(file.date) > Self.maxAge {
                try? FileManager.default.removeItem(at: file.url)
            }
            files.removeAll { now.timeIntervalSince($0.date) > Self.maxAge }
            var total = files.reduce(0) { $0 + $1.size }
            for file in files.reversed() where total > Self.maxBytes {
                try? FileManager.default.removeItem(at: file.url)
                total -= file.size
            }
        }
    }

    /// Adds lines to this launch's file, as long as it stays within the
    /// limit; the last line then says it stopped.
    func append(_ lines: [String]) {
        lock.withLock {
            guard !isFull, !lines.isEmpty else { return }
            let size = (try? currentFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            var text = lines.joined(separator: "\n") + "\n"
            if size + text.utf8.count > Self.maxBytes {
                text = "(the log of this launch passed \(Self.maxBytes / 1024 / 1024) MB; nothing more is kept)\n"
                isFull = true
            }
            guard let data = text.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: currentFile) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: currentFile)
            }
        }
    }

    /// Copies the entries logged since the last call. Reads the system log,
    /// which takes a moment: call it off the main thread.
    func copyNewEntries() {
        let since = lock.withLock { copiedUntil }
        let entries = Self.entries(since: since)
        guard let last = entries.last else { return }
        lock.withLock { copiedUntil = last.date }
        append(entries.map(\.line))
    }

    /// Every launch before this one, oldest first, as name and text.
    func earlierLaunches() -> [(name: String, text: String)] {
        lock.withLock {
            earlierFiles().reversed().compactMap { file in
                (try? String(contentsOf: file.url, encoding: .utf8)).map { (file.url.deletingPathExtension().lastPathComponent, $0) }
            }
        }
    }

    /// The other launches' files, newest first.
    private func earlierFiles() -> [(url: URL, date: Date, size: Int)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension == "log" && $0.lastPathComponent != currentFile.lastPathComponent }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return (url, values?.contentModificationDate ?? .distantPast, values?.fileSize ?? 0)
            }
            .sorted { $0.date > $1.date }
    }

    /// KeyBridge's own entries in this process's log, after `date` when
    /// given, one formatted line each.
    static func entries(since date: Date? = nil, limit: Int = 5000) -> [(date: Date, line: String)] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let subsystem = Bundle.main.bundleIdentifier ?? "KeyBridge"
            let position = date.map { store.position(date: $0) }
            let entries = try store.getEntries(at: position, matching: NSPredicate(format: "subsystem == %@", subsystem))
            let lines = entries.compactMap { entry -> (Date, String)? in
                guard let log = entry as? OSLogEntryLog, date.map({ log.date > $0 }) ?? true else { return nil }
                return (log.date, "\(DiagnosticReport.timestamp(log.date)) \(levelName(log.level)) [\(log.category)] \(log.composedMessage)")
            }
            return Array(lines.suffix(limit))
        } catch {
            return [(.now, "(the log could not be read: \(error.localizedDescription))")]
        }
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "-"
        }
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }
}
