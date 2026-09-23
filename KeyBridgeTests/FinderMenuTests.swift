import Foundation
import Testing

/// The Finder menu's file naming and the requests its extension sends (KB-210).
@Suite struct FinderMenuTests {
    let folder = URL(filePath: "/Users/someone/My Folder", directoryHint: .isDirectory)

    @Test func firstFileTakesThePlainName() {
        let url = NewDocument.freeURL(for: .text, in: folder) { _ in false }
        #expect(url.lastPathComponent == "New Text Document.txt")
        #expect(url.deletingLastPathComponent().path() == folder.path())
    }

    @Test func takenNamesAreNumberedLikeFinderCopies() {
        let taken: Set = ["New Word Document.docx", "New Word Document 2.docx"]
        let url = NewDocument.freeURL(for: .word, in: folder) { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "New Word Document 3.docx")
    }

    @Test func aNameTakenByAnotherTypeDoesNotCount() {
        let url = NewDocument.freeURL(for: .markdown, in: folder) { $0.lastPathComponent == "New Text Document.txt" }
        #expect(url.lastPathComponent == "New Markdown Document.md")
    }

    @Test func everyKindHasItsOwnExtension() {
        let extensions = NewDocument.allCases.map(\.fileExtension)
        #expect(Set(extensions).count == extensions.count)
        #expect(NewDocument.keynote.fileExtension == "key")
    }

    @Test func officeKindsShipATemplateAndPlainTextStartsEmpty() {
        #expect(NewDocument.text.source == .empty)
        #expect(NewDocument.markdown.source == .empty)
        #expect(NewDocument.word.source == .bundled("Blank.docx"))
        #expect(NewDocument.excel.source == .bundled("Blank.xlsx"))
        #expect(NewDocument.powerPoint.source == .bundled("Blank.pptx"))
    }

    @Test func bundledTemplatesExistInTheRepository() {
        let templates = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "KeyBridge/Resources/Templates")
        for document in NewDocument.allCases {
            if case let .bundled(name) = document.source {
                #expect(FileManager.default.fileExists(atPath: templates.appending(path: name).path()), "\(name)")
            }
        }
    }

    @Test func requestsSurviveTheRoundTrip() {
        let odd = URL(filePath: "/Volumes/USB Stick/报告 & notes?#1", directoryHint: .isDirectory)
        for request in [FinderMenuRequest.new(.powerPoint, folder: folder),
                        .new(.pages, folder: odd),
                        .openTerminal(folder: odd)] {
            #expect(FinderMenuRequest(url: request.url) == request)
        }
    }

    @Test func copyPathJoinsOnePathPerLine() {
        let a = URL(filePath: "/Users/someone/My Folder/a.txt")
        let b = URL(filePath: "/Volumes/USB Stick/报告 & notes?#1", directoryHint: .isDirectory)
        #expect(CopyPath.text(for: [a]) == "/Users/someone/My Folder/a.txt")
        #expect(CopyPath.text(for: [a, b]) == "/Users/someone/My Folder/a.txt\n/Volumes/USB Stick/报告 & notes?#1/")
    }

    @Test func foreignOrMalformedURLsAreRefused() {
        let refused = [
            "https://finder/new?type=text&folder=/tmp",
            "keybridge://other/new?type=text&folder=/tmp",
            "keybridge://finder/new?type=exe&folder=/tmp",
            "keybridge://finder/new?type=text",
            "keybridge://finder/new?type=text&folder=relative/path",
            "keybridge://finder/delete?folder=/tmp",
        ]
        for string in refused {
            #expect(FinderMenuRequest(url: URL(string: string)!) == nil, "\(string)")
        }
    }
}
