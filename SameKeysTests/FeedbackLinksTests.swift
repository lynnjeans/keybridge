import Foundation
import Testing

/// About › Feedback (SK-280).
@Suite struct FeedbackLinksTests {
    @Test func theMailIsAddressedWithTheVersionsFilledIn() throws {
        let url = FeedbackLinks.mail(app: "1.2 (3)", system: "26.6.2 (25G83)")
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == FeedbackLinks.address)
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["subject"] == "SameKeys 1.2 (3)")
        #expect(items["body"]?.contains("SameKeys 1.2 (3)\nmacOS 26.6.2 (25G83)") == true)
        #expect(!url.absoluteString.contains(" "), "Spaces are escaped, or mail apps drop the rest")
    }

    @Test func theIssueIsTheProblemFormWithTheVersions() throws {
        let url = FeedbackLinks.issue(app: "1.2 (3)", system: "26.6.2 (25G83)")
        #expect(url.absoluteString.hasPrefix("https://github.com/lynnjeans/samekeys/issues/new?"))
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        #expect(items == ["template": "problem.yml", "app-version": "1.2 (3)", "macos-version": "26.6.2 (25G83)"])
    }

    /// The query names the form and its fields; renaming either there
    /// would quietly leave the versions out.
    @Test func theFormHasTheFieldsTheLinkFills() throws {
        let form = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".github/ISSUE_TEMPLATE/problem.yml")
        let text = try String(contentsOf: form, encoding: .utf8)
        #expect(text.contains("id: app-version"))
        #expect(text.contains("id: macos-version"))
    }

    @Test func theAddressIsOnTheAppsOwnDomain() {
        #expect(FeedbackLinks.address.hasSuffix("@samekeys.com"))
    }
}
