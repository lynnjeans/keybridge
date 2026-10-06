import Foundation

/// Where About › Feedback sends people (SK-280): a new GitHub issue, or a
/// new mail to SameKeys's own address. Both start with the versions filled
/// in, the first thing anyone needs to answer a report.
enum FeedbackLinks {
    /// On samekeys.com and forwarded by Cloudflare Email Routing, so the
    /// inbox behind it can change without a release.
    static let address = "hello@samekeys.com"
    static let newIssue = URL(string: "https://github.com/lynnjeans/samekeys/issues/new")!

    /// The lines that close a report: SameKeys's and macOS's versions.
    static func versions(app: String, system: String) -> String {
        "\n\n—\nSameKeys \(app)\nmacOS \(system)\n"
    }

    static func issue(app: String, system: String) -> URL {
        var components = URLComponents(url: newIssue, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "body", value: versions(app: app, system: system))]
        return components.url!
    }

    static func mail(app: String, system: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "SameKeys \(app)"),
            URLQueryItem(name: "body", value: versions(app: app, system: system)),
        ]
        return components.url!
    }

    /// This copy's version as About shows it, such as "1.2 (3)".
    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
