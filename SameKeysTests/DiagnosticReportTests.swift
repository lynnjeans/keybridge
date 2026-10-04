import Foundation
import Testing

@Suite struct DiagnosticReportTests {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func laysOutSectionsConfigurationAndLog() {
        let report = DiagnosticReport(
            generated: Self.date,
            sections: [.init(title: "State", lines: [("Event tap running", "yes")])],
            configuration: "{\n  \"version\" : 1\n}",
            log: ["one", "two"]
        )
        let text = report.text
        #expect(text.hasPrefix("SameKeys diagnostics\nGenerated: "))
        #expect(text.contains("\n## State\nEvent tap running: yes\n"))
        #expect(text.contains("\n## Configuration file\n{\n  \"version\" : 1\n}\n"))
        #expect(text.contains("\n## Log since launch (2 entries)\none\ntwo\n"))
        #expect(text.hasSuffix("\n## Earlier launches (0, last three days)\n(none kept)\n"))
    }

    @Test func saysWhenThereIsNoConfigurationOrLog() {
        let text = DiagnosticReport(generated: Self.date, sections: [], configuration: nil, log: []).text
        #expect(text.contains("## Configuration file\n(none yet: the built-in defaults are in use)"))
        #expect(text.contains("## Log since launch (0 entries)\n(empty)"))
        #expect(text.contains("## Recording\n(none made: "))
    }

    @Test func leavesTheAccountNameOut() {
        let home = NSHomeDirectory()
        let report = DiagnosticReport(
            generated: Self.date,
            sections: [.init(title: "App", lines: [("Location", home + "/Applications/SameKeys.app")])],
            configuration: nil,
            log: ["Moved the unreadable file to \(home)/Library/Application Support/SameKeys/config.broken.json"]
        )
        #expect(!report.text.contains(home))
        #expect(report.text.contains("Location: ~/Applications/SameKeys.app"))
        #expect(report.text.contains("to ~/Library/Application Support/SameKeys/config.broken.json"))
    }

    @Test func timestampsAreLocalWithTheOffset() {
        #expect(DiagnosticReport.timestamp(Self.date, timeZone: TimeZone(identifier: "UTC")!)
                == "2026-09-21 14:13:20.000 +00:00")
        // Before New Zealand's daylight saving starts on 27 September.
        #expect(DiagnosticReport.timestamp(Self.date, timeZone: TimeZone(identifier: "Pacific/Auckland")!)
                == "2026-09-22 02:13:20.000 +12:00")
    }
}
