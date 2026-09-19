import Foundation

/// What a problem report needs from KeyBridge, as a plain-text file the user
/// attaches: versions, permissions, what is running, the settings in full
/// and the log since launch. Never anything the user copied: the clipboard
/// history appears only as a count.
///
/// Written in English whatever the interface language, for whoever reads
/// the report.
struct DiagnosticReport {
    struct Section {
        var title: String
        var lines: [(label: String, value: String)]
    }

    var generated: Date
    var sections: [Section]
    /// The configuration file as saved, or nil when there is none yet.
    var configuration: String?
    var log: [String]

    var text: String {
        var parts = ["KeyBridge diagnostics", "Generated: \(Self.timestamp(generated))"]
        for section in sections {
            parts.append("")
            parts.append("## \(section.title)")
            parts += section.lines.map { "\($0.label): \($0.value)" }
        }
        parts.append("")
        parts.append("## Configuration file")
        parts.append(configuration ?? "(none yet: the built-in defaults are in use)")
        parts.append("")
        parts.append("## Log since launch (\(log.count) entries)")
        parts += log.isEmpty ? ["(empty)"] : log
        return Self.abbreviatingHome(parts.joined(separator: "\n") + "\n")
    }

    /// The text with the user's home folder written as `~`, so paths in
    /// the settings or the log do not carry the account name.
    static func abbreviatingHome(_ text: String, home: String = NSHomeDirectory()) -> String {
        guard home.count > 1 else { return text }
        return text.replacingOccurrences(of: home, with: "~")
    }

    /// The macOS version and build, such as "26.6.2 (25G83)" — not
    /// `operatingSystemVersionString`, which is in the user's language.
    static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) (\(sysctl("kern.osversion") ?? "?"))"
    }

    /// The Mac's model identifier, such as "Mac17,4".
    static var hardwareModel: String { sysctl("hw.model") ?? "?" }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Local time with its offset, the way the log shows it.
    static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS xxx"
        return formatter.string(from: date)
    }
}
