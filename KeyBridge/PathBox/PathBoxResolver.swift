import Foundation

/// What a path pasted into the path box (KB-213) resolves to.
enum PathBoxTarget: Equatable {
    /// Navigate straight here.
    case folder(URL)
    /// Navigate to the containing folder and select this.
    case file(URL)
}

/// Turns what was pasted or typed into the box into something Finder can be
/// sent to. Pure, and touches the file system only through `FileManager`, so
/// it is testable without a real Finder.
enum PathBoxResolver {
    /// Nil for empty input, or a path nothing exists at.
    static func resolve(_ text: String, fileManager: FileManager = .default) -> PathBoxTarget? {
        let trimmed = clean(text)
        guard !trimmed.isEmpty else { return nil }
        let path = (trimmed as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? .folder(URL(fileURLWithPath: path)) : .file(URL(fileURLWithPath: path))
    }

    /// Trims whitespace/newlines and one pair of wrapping quotes, the shape
    /// Windows' own "Copy as path" and a shell's `pwd` sometimes leave.
    static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count >= 2, result.hasPrefix("\""), result.hasSuffix("\"") {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }
}
