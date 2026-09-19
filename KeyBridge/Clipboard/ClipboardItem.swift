import AppKit
import Foundation

/// One copy, kept with every form it was copied in that KeyBridge knows how
/// to give back, so pasting it later brings back rich text as rich text and
/// an image as an image.
struct ClipboardItem: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    /// The app it was copied from, when known.
    var sourceBundleID: String?
    /// Pasteboard type identifier → contents, for the kept types only.
    var contents: [String: Data]
    var isPinned = false

    /// The forms kept, in the order they are offered back. Anything else an
    /// app puts on the pasteboard, such as private formats, is left out.
    static let keptTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .png, .tiff, .rtf, .html, .string,
    ]

    enum Kind: Sendable {
        case text, richText, image, file
    }

    var kind: Kind {
        if contents[NSPasteboard.PasteboardType.fileURL.rawValue] != nil { return .file }
        if contents[NSPasteboard.PasteboardType.png.rawValue] != nil
            || contents[NSPasteboard.PasteboardType.tiff.rawValue] != nil { return .image }
        if contents[NSPasteboard.PasteboardType.rtf.rawValue] != nil
            || contents[NSPasteboard.PasteboardType.html.rawValue] != nil { return .richText }
        return .text
    }

    /// The plain text, if it has any.
    var text: String? {
        contents[NSPasteboard.PasteboardType.string.rawValue].flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The copied file's URL, for a file.
    var fileURL: URL? {
        contents[NSPasteboard.PasteboardType.fileURL.rawValue]
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(URL.init(string:))
    }

    /// Whether this is the same copy as `other`, ignoring when and where:
    /// copying the same thing again moves it to the top instead of adding it.
    func hasSameContents(as other: ClipboardItem) -> Bool {
        contents == other.contents
    }
}
