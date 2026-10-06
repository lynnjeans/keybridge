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

    @Test func theIssueStartsWithTheVersions() throws {
        let url = FeedbackLinks.issue(app: "1.2 (3)", system: "26.6.2 (25G83)")
        #expect(url.absoluteString.hasPrefix("https://github.com/lynnjeans/samekeys/issues/new?body="))
        let body = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
        #expect(body?.hasSuffix("macOS 26.6.2 (25G83)\n") == true)
    }

    @Test func theAddressIsOnTheAppsOwnDomain() {
        #expect(FeedbackLinks.address.hasSuffix("@samekeys.com"))
    }
}
