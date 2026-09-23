import Foundation
import Testing

/// What pasted text resolves to for the paste-a-path box (KB-213).
@Suite struct PathBoxTests {
    private let files = FileManager.default
    private let folder = FileManager.default.temporaryDirectory.appending(path: "PathBoxTests-\(UUID().uuidString)")

    private func withFixture(_ body: (URL) throws -> Void) rethrows {
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        try body(folder)
    }

    @Test func aFolderResolvesToItself() {
        withFixture { folder in
            // `URL(fileURLWithPath:)` — what the resolver itself builds from
            // — adds a trailing slash once the directory exists on disk, so
            // the expected value is built the same way rather than reusing
            // `folder`, whose URL was made before the directory existed.
            let expected = URL(fileURLWithPath: folder.path(percentEncoded: false))
            #expect(PathBoxResolver.resolve(folder.path(percentEncoded: false)) == .folder(expected))
        }
    }

    @Test func aFileResolvesToItselfForSelection() throws {
        try withFixture { folder in
            let file = folder.appending(path: "a.txt")
            try Data().write(to: file)
            #expect(PathBoxResolver.resolve(file.path(percentEncoded: false)) == .file(file))
        }
    }

    @Test func aMissingPathResolvesToNil() {
        #expect(PathBoxResolver.resolve("/definitely/not/a/real/path/\(UUID().uuidString)") == nil)
    }

    @Test func emptyOrBlankInputResolvesToNil() {
        #expect(PathBoxResolver.resolve("") == nil)
        #expect(PathBoxResolver.resolve("   \n\t  ") == nil)
    }

    @Test func surroundingWhitespaceAndQuotesAreStripped() {
        withFixture { folder in
            let path = folder.path(percentEncoded: false)
            let expected = URL(fileURLWithPath: path)
            #expect(PathBoxResolver.resolve("  \(path)  \n") == .folder(expected))
            #expect(PathBoxResolver.resolve("\"\(path)\"") == .folder(expected))
        }
    }

    @Test func tildeExpandsToTheHomeDirectory() {
        let home = files.homeDirectoryForCurrentUser
        #expect(PathBoxResolver.resolve("~") == .folder(URL(fileURLWithPath: home.path(percentEncoded: false))))
    }

    @Test func aBundleResolvesToAFileSoItIsRevealedRatherThanLaunched() throws {
        try withFixture { folder in
            // A bundle is a directory on disk; opening one would launch or
            // open it instead of showing it in Finder.
            let bundle = folder.appending(path: "Example.app")
            try files.createDirectory(at: bundle, withIntermediateDirectories: true)
            let path = bundle.path(percentEncoded: false)
            #expect(PathBoxResolver.resolve(path) == .file(URL(fileURLWithPath: path)))
        }
    }

    @Test func onlyTheFirstLineOfAMultipleSelectionIsUsed() {
        withFixture { folder in
            // KeyBridge's own Copy Path writes one path per line.
            let path = folder.path(percentEncoded: false)
            let pasted = "\(path)\n/definitely/not/a/real/path\n"
            #expect(PathBoxResolver.resolve(pasted) == .folder(URL(fileURLWithPath: path)))
        }
    }

    @Test func aSingleQuoteIsLeftAlone() {
        // Not a matched pair, so it is part of the path, not a wrapper — and
        // a lone quote can never be a real path anyway.
        #expect(PathBoxResolver.clean("\"/tmp") == "\"/tmp")
    }
}
