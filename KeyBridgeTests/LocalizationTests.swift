import Foundation
import Testing

/// Every string the UI shows must exist in every language KeyBridge ships.
/// A string added without translations fails here, so the gap is seen before
/// a release rather than by a user.
@Suite struct LocalizationTests {
    static let languages = ["zh-Hans", "ja"]

    let strings: [String: [String: Any]] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "KeyBridge/Resources/Localizable.xcstrings")
        let data = try! Data(contentsOf: url)
        let catalog = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        return catalog["strings"] as! [String: [String: Any]]
    }()

    @Test func everyStringIsTranslated() {
        var missing: [String] = []
        for (key, entry) in strings where entry["shouldTranslate"] as? Bool != false {
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in Self.languages where localizations[language] == nil {
                missing.append("\(language): \(key)")
            }
        }
        #expect(missing.isEmpty, "Untranslated: \(missing.sorted())")
    }

    @Test func translationsKeepEveryPlaceholder() throws {
        let placeholder = try Regex(#"%(?:\d\$)?(lld|@)"#)
        func kinds(_ text: String) -> [String] {
            text.matches(of: placeholder).map { String(text[$0.range].last!) }.sorted()
        }
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String: [String: [String: String]]] ?? [:]
            for (language, localization) in localizations {
                let value = localization["stringUnit"]?["value"] ?? ""
                #expect(kinds(value) == kinds(key), "\(language): \(key)")
            }
        }
    }
}
