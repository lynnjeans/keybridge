import AppKit
import UniformTypeIdentifiers

// Shared by the app and its Finder extension (KB-210): the extension builds
// the menu from it, and the app creates what was chosen.

/// A kind of file the Finder menu's New submenu creates.
enum NewDocument: String, CaseIterable, Sendable {
    case text, markdown, word, excel, powerPoint, pages, numbers, keynote

    var fileExtension: String {
        switch self {
        case .text: "txt"
        case .markdown: "md"
        case .word: "docx"
        case .excel: "xlsx"
        case .powerPoint: "pptx"
        case .pages: "pages"
        case .numbers: "numbers"
        case .keynote: "key"
        }
    }

    /// The item in the New submenu.
    var menuTitle: String {
        switch self {
        case .text: String(localized: "Text Document", bundle: .keyBridge)
        case .markdown: String(localized: "Markdown Document", bundle: .keyBridge)
        case .word: String(localized: "Word Document", bundle: .keyBridge)
        case .excel: String(localized: "Excel Workbook", bundle: .keyBridge)
        case .powerPoint: String(localized: "PowerPoint Presentation", bundle: .keyBridge)
        case .pages: String(localized: "Pages Document", bundle: .keyBridge)
        case .numbers: String(localized: "Numbers Spreadsheet", bundle: .keyBridge)
        case .keynote: String(localized: "Keynote Presentation", bundle: .keyBridge)
        }
    }

    /// A new file's name without its extension, as Windows names them.
    var baseName: String {
        switch self {
        case .text: String(localized: "New Text Document", bundle: .keyBridge)
        case .markdown: String(localized: "New Markdown Document", bundle: .keyBridge)
        case .word: String(localized: "New Word Document", bundle: .keyBridge)
        case .excel: String(localized: "New Excel Workbook", bundle: .keyBridge)
        case .powerPoint: String(localized: "New PowerPoint Presentation", bundle: .keyBridge)
        case .pages: String(localized: "New Pages Document", bundle: .keyBridge)
        case .numbers: String(localized: "New Numbers Spreadsheet", bundle: .keyBridge)
        case .keynote: String(localized: "New Keynote Presentation", bundle: .keyBridge)
        }
    }

    /// Where a new file's content comes from.
    enum Source: Equatable {
        /// Plain text starts empty.
        case empty
        /// A blank document shipped in the app's Templates folder, written by
        /// scripts/make-office-templates.py: Office cannot open an empty file.
        case bundled(String)
        /// The blank template inside the user's own copy of an iWork app,
        /// which opens as an ordinary document once renamed. Copying it at
        /// run time means KeyBridge redistributes no Apple file. Paths are
        /// relative to the app's Templates folder, preferred first.
        case appTemplate(bundleID: String, paths: [String])
    }

    var source: Source {
        switch self {
        case .text, .markdown: .empty
        case .word: .bundled("Blank.docx")
        case .excel: .bundled("Blank.xlsx")
        case .powerPoint: .bundled("Blank.pptx")
        case .pages:
            // Letter-sized paper where Letter is the norm, A4 elsewhere.
            .appTemplate(bundleID: "com.apple.Pages", paths: Self.usesLetterPaper
                         ? ["Blank/Traditional.template", "Blank/ISO.template"]
                         : ["Blank/ISO.template", "Blank/Traditional.template"])
        case .numbers:
            .appTemplate(bundleID: "com.apple.Numbers", paths: ["Blank/Traditional.nmbtemplate"])
        case .keynote:
            .appTemplate(bundleID: "com.apple.Keynote",
                         paths: ["White/Wide.kth", "21_BasicWhite/Wide.kth", "White/Standard.kth"])
        }
    }

    /// The template to copy, when this kind comes from an installed app and
    /// the app has one; nil when the app or its template is missing.
    var appTemplate: URL? {
        guard case let .appTemplate(bundleID, paths) = source,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let templates = app.appending(path: "Contents/SharedSupport/Templates")
        return paths.lazy
            .map { templates.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// Whether the menu lists this kind. Plain text always; an Office format
    /// when some app opens it (TextEdit opens .docx, Numbers .xlsx); an iWork
    /// format when its app and template are installed. On Windows too, New
    /// only lists what the PC can open.
    var isAvailable: Bool {
        switch source {
        case .empty: true
        case .bundled: UTType(filenameExtension: fileExtension)
            .flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) } != nil
        case .appTemplate: appTemplate != nil
        }
    }

    /// The icon Finder shows for files of this kind.
    var icon: NSImage {
        let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: fileExtension) ?? .data)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    /// The first name of the form "New Text Document.txt", "New Text
    /// Document 2.txt", … in `folder` that `exists` says is free. Numbered as
    /// Finder numbers copies, not with Windows' "(2)".
    static func freeURL(for document: NewDocument, in folder: URL, exists: (URL) -> Bool) -> URL {
        var number = 1
        while true {
            let name = number == 1 ? document.baseName : "\(document.baseName) \(number)"
            let url = folder.appending(path: name).appendingPathExtension(document.fileExtension)
            if !exists(url) { return url }
            number += 1
        }
    }

    private static var usesLetterPaper: Bool {
        let letterRegions: Set = ["US", "CA", "MX", "PR", "PH", "CL", "CO", "VE", "GT", "CR", "PA", "DO", "SV"]
        return letterRegions.contains(Locale.current.region?.identifier ?? "")
    }
}

/// The Finder menu's other titles. They live here rather than in the
/// extension so they are extracted into the app's string catalog with the rest.
enum FinderMenuTitle {
    static var new: String { String(localized: "New", bundle: .keyBridge) }
    static var openInTerminal: String { String(localized: "Open in Terminal", bundle: .keyBridge) }
}

/// What the Finder extension asks the app to do.
///
/// The extension runs in the App Sandbox and may not write to the user's
/// folders, so it passes the choice to KeyBridge, which is not sandboxed, as
/// a `keybridge://` URL. Opening a URL also launches KeyBridge when it is not
/// running.
enum FinderMenuRequest: Equatable, Sendable {
    case new(NewDocument, folder: URL)
    case openTerminal(folder: URL)

    static let scheme = "keybridge"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "finder"
        switch self {
        case let .new(document, folder):
            components.path = "/new"
            components.queryItems = [.init(name: "type", value: document.rawValue),
                                     .init(name: "folder", value: folder.path(percentEncoded: false))]
        case let .openTerminal(folder):
            components.path = "/terminal"
            components.queryItems = [.init(name: "folder", value: folder.path(percentEncoded: false))]
        }
        return components.url!
    }

    /// Reads a request back, or nil for any URL KeyBridge did not make. The
    /// folder must be an absolute path; the file name never comes from the URL.
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme, components.host == "finder" else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let path = value("folder"), path.hasPrefix("/") else { return nil }
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        switch components.path {
        case "/new":
            guard let document = value("type").flatMap(NewDocument.init(rawValue:)) else { return nil }
            self = .new(document, folder: folder)
        case "/terminal":
            self = .openTerminal(folder: folder)
        default:
            return nil
        }
    }
}

extension Bundle {
    /// KeyBridge.app's bundle, which holds the strings, also when this code
    /// runs in the Finder extension inside it (Contents/PlugIns/….appex).
    static let keyBridge: Bundle = {
        let main = Bundle.main
        guard main.bundleURL.pathExtension == "appex" else { return main }
        let app = main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: app) ?? main
    }()
}
