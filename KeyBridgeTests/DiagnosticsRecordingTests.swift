import CoreGraphics
import Foundation
import Testing

/// What a report shows of what happened (KB-247): a recording of shortcuts,
/// the settings each keyboard actually runs with, and earlier launches' logs.
@MainActor
@Suite struct DiagnosticsRecordingTests {
    private typealias Keyboards = PerKeyboardTests
    private let keyboards = PerKeyboardTests()
    private let utc = TimeZone(identifier: "UTC")!
    private let closeTab = Rule(id: "browser.closeTab", trigger: .key(combo: KeyCombo([.control], .w)),
                                action: .key(combo: KeyCombo([.command], .w)))

    private func trace(_ combo: KeyCombo, rule: Rule? = nil) -> DispatchTrace {
        DispatchTrace(trigger: .key(combo: combo), keyboard: .software, frontmostBundleID: nil, rule: rule)
    }

    // MARK: - What is recorded

    @Test func plainTypingIsNeverRecorded() {
        #expect(!trace(KeyCombo(.a)).isWorthRecording)
        #expect(!trace(KeyCombo([.shift], .a)).isWorthRecording, "Capitals are typing too")
        #expect(!trace(KeyCombo(.returnKey)).isWorthRecording)
        #expect(!trace(KeyCombo(.delete)).isWorthRecording)
        #expect(!trace(KeyCombo(.leftArrow)).isWorthRecording)
    }

    @Test func charactersTypedWithOptionAreTypingToo() {
        #expect(!trace(KeyCombo([.option], .a)).isWorthRecording, "ą on Polish Pro")
        #expect(!trace(KeyCombo([.option, .shift], .a)).isWorthRecording, "Ą")
        #expect(!trace(KeyCombo([.option], .l)).isWorthRecording, "@ on German")
        #expect(!trace(KeyCombo([.option], .four)).isWorthRecording)
        #expect(!trace(KeyCombo([.option], .leftArrow)).isWorthRecording, "Word by word, while snapping is off")
        let snap = Rule(id: "window.leftHalf", trigger: .key(combo: KeyCombo([.option], .leftArrow)),
                        action: .windowAction(.leftHalf))
        #expect(trace(KeyCombo([.option], .leftArrow), rule: snap).isWorthRecording, "A key a rule took")
        #expect(trace(KeyCombo([.option], .f4)).isWorthRecording)
        #expect(trace(KeyCombo(.option)).isWorthRecording, "Option tapped alone")
        #expect(trace(KeyCombo([.option, .command], .a)).isWorthRecording)
        #expect(trace(KeyCombo([.option, .control], .a)).isWorthRecording)
    }

    @Test func shortcutsAndKeysThatTypeNothingAre() {
        #expect(trace(KeyCombo([.control], .w)).isWorthRecording)
        #expect(trace(KeyCombo([.function, .shift], .a)).isWorthRecording)
        #expect(trace(KeyCombo(.f13)).isWorthRecording, "Print Screen")
        #expect(trace(KeyCombo(.home)).isWorthRecording)
        #expect(trace(KeyCombo(.command)).isWorthRecording, "Win tapped alone")
        let open = Rule(id: "finder.open", trigger: .key(combo: KeyCombo(.returnKey)),
                        action: .key(combo: KeyCombo([.command], .downArrow)))
        #expect(trace(KeyCombo(.returnKey), rule: open).isWorthRecording, "A key a rule took")
        let button = DispatchTrace(trigger: .mouseButton(number: 4), keyboard: .lastModifier(nil),
                                   frontmostBundleID: nil, rule: nil)
        #expect(button.isWorthRecording)
    }

    @Test func aLineSaysWhatCameInFromWhereAndWhatItBecame() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        var entry = DispatchTrace(trigger: .key(combo: KeyCombo([.control], .w)), keyboard: .keyboard(Keyboards.external),
                                  frontmostBundleID: "com.apple.finder", rule: closeTab)
        #expect(entry.line(at: date, timeZone: utc)
                == "14:13:20.000 ⌃W  keyboard: RK-KB5.0 (0x000e/0x3412)  app: com.apple.finder  → browser.closeTab: ⌘W")
        entry.keyboard = .unknown(sender: 0x1_0001_6948)
        entry.rule = nil
        #expect(entry.line(at: date, timeZone: utc)
                == "14:13:20.000 ⌃W  keyboard: unknown (sender 0x100016948)  app: com.apple.finder  → no match")
        let button = DispatchTrace(trigger: .mouseButton(number: 4), keyboard: .lastModifier(nil), frontmostBundleID: nil,
                                   rule: Rule(id: "mouse.back", trigger: .mouseButton(number: 4), action: .clipboardHistory))
        #expect(button.line(at: date, timeZone: utc)
                == "14:13:20.000 button 4  keyboard: last modifier's, not told  app: none  → mouse.back: clipboard history")
    }

    // MARK: - The dispatcher

    private func makeDispatcher(_ traces: Box) -> Dispatcher {
        let dispatcher = Dispatcher(
            frontmostBundleID: { "com.apple.finder" },
            keyboard: { event in
                Int64(bitPattern: event.senderID) == Keyboards.externalSender ? Keyboards.external : nil
            }
        )
        dispatcher.rules = [closeTab]
        return dispatcher
    }

    final class Box { var traces: [DispatchTrace] = [] }

    @Test func nothingIsAskedOrKeptWhileNotRecording() throws {
        let box = Box()
        let dispatcher = makeDispatcher(box)
        _ = dispatcher.process(try keyboards.key(.w, .maskControl, from: Keyboards.externalSender), type: .keyDown)
        #expect(box.traces.isEmpty)
    }

    @Test func aRecordingNotesEachShortcutWithItsKeyboard() throws {
        let box = Box()
        let dispatcher = makeDispatcher(box)
        dispatcher.trace = { box.traces.append($0) }
        _ = dispatcher.process(try keyboards.key(.w, .maskControl, from: Keyboards.externalSender), type: .keyDown)
        _ = dispatcher.process(try keyboards.key(.a, [], from: Keyboards.externalSender), type: .keyDown)
        _ = dispatcher.process(try keyboards.key(.e, .maskControl, from: 0x1_0000_0001), type: .keyDown)
        _ = dispatcher.process(try keyboards.key(.e, .maskCommand, from: nil), type: .keyDown)
        #expect(box.traces.count == 3, "The plain A is left out")
        #expect(box.traces[0].keyboard == .keyboard(Keyboards.external))
        #expect(box.traces[0].rule?.id == closeTab.id)
        #expect(box.traces[0].frontmostBundleID == "com.apple.finder")
        #expect(box.traces[1].keyboard == .unknown(sender: 0x1_0000_0001))
        #expect(box.traces[1].rule == nil)
        #expect(box.traces[2].keyboard == .software)
    }

    @Test func theRecorderAttachesKeepsAndLetsGo() {
        var attached: (@MainActor (DispatchTrace) -> Void)?
        let recorder = DiagnosticRecorder(attach: { attached = $0 })
        recorder.start(for: 60)
        #expect(recorder.isRecording)
        attached?(trace(KeyCombo([.control], .w)))
        #expect(recorder.lines.count == 1)
        recorder.stop()
        #expect(attached == nil)
        #expect(!recorder.isRecording)
        #expect(recorder.lines.count == 1, "Kept for the next export")
        recorder.start(for: 60)
        #expect(recorder.lines.isEmpty, "A new recording starts empty")
        recorder.stop()
    }

    @Test func aLongRecordingKeepsTheNewest() {
        let recorder = DiagnosticRecorder(attach: { _ in })
        for _ in 0..<(DiagnosticRecorder.lineLimit + 5) { recorder.add(trace(KeyCombo([.control], .w))) }
        #expect(recorder.lines.count == DiagnosticRecorder.lineLimit)
    }

    // MARK: - Keyboards in effect

    @Test func eachKeyboardShowsWhatItRunsWithAndWhy() {
        var configuration = Configuration()
        configuration.controlKey = .function
        configuration.modifierLayout = .macPosition
        let lines = DiagnosticReport.effectiveSettings(of: [Keyboards.builtIn, Keyboards.external], in: configuration)
        #expect(lines[0] == "Apple Internal Keyboard / Trackpad (built-in): Ctrl shortcuts fn (general), Win and Alt mac (general)")
        #expect(lines[1] == "RK-KB5.0 (0x000e/0x3412): Ctrl shortcuts control (PC keyboard default), Win and Alt pc (PC keyboard default)")
        configuration.setModifierLayout(.macPosition, for: Keyboards.external)
        #expect(DiagnosticReport.effectiveSettings(of: [Keyboards.external], in: configuration)[0]
                == "RK-KB5.0 (0x000e/0x3412): Ctrl shortcuts control (PC keyboard default), Win and Alt mac (its own)")
    }

    // MARK: - Earlier launches

    private func makeFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "KeyBridgeLogs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func write(_ text: String, _ name: String, in folder: URL, age: TimeInterval, now: Date) throws {
        let url = folder.appending(path: name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    @Test func earlierLaunchesAreKeptOldestFirstAndThisOneLeftOut() throws {
        let folder = makeFolder()
        let now = Date.now
        try write("first\n", "KeyBridge 2026-10-01 09.00.00.log", in: folder, age: 7200, now: now)
        try write("second\n", "KeyBridge 2026-10-02 09.00.00.log", in: folder, age: 3600, now: now)
        let archive = LogArchive(folder: folder, launch: now)
        archive.prune(now: now)
        archive.append(["this launch"])
        let launches = archive.earlierLaunches()
        #expect(launches.map(\.name) == ["KeyBridge 2026-10-01 09.00.00", "KeyBridge 2026-10-02 09.00.00"])
        #expect(launches.map(\.text) == ["first\n", "second\n"])
        #expect(try String(contentsOf: archive.currentFile, encoding: .utf8) == "this launch\n")
        archive.append(["more"])
        #expect(try String(contentsOf: archive.currentFile, encoding: .utf8) == "this launch\nmore\n")
    }

    @Test func oldAndExcessLogsGo() throws {
        let folder = makeFolder()
        let now = Date.now
        try write("old\n", "KeyBridge old.log", in: folder, age: LogArchive.maxAge + 60, now: now)
        let big = String(repeating: "x", count: LogArchive.maxBytes / 2 + 10)
        try write(big, "KeyBridge a.log", in: folder, age: 300, now: now)
        try write(big, "KeyBridge b.log", in: folder, age: 200, now: now)
        try write("small\n", "KeyBridge c.log", in: folder, age: 100, now: now)
        LogArchive(folder: folder, launch: now).prune(now: now)
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(left == ["KeyBridge b.log", "KeyBridge c.log"], "Too old, then the oldest until within the limit")
    }

    @Test func aLaunchStopsWritingAtTheLimit() throws {
        let archive = LogArchive(folder: makeFolder(), launch: .now)
        archive.prune()
        archive.append([String(repeating: "x", count: LogArchive.maxBytes - 10)])
        archive.append(["one more line that does not fit"])
        archive.append(["nor this"])
        let text = try String(contentsOf: archive.currentFile, encoding: .utf8)
        #expect(text.hasSuffix("MB; nothing more is kept)\n"))
        #expect(!text.contains("nor this"))
    }

    @Test func theReportCarriesTheRecordingAndEarlierLaunches() {
        let report = DiagnosticReport(
            generated: .now, sections: [], configuration: nil,
            recording: .init(started: Date(timeIntervalSince1970: 1_790_000_000), isRunning: false, lines: ["a line"]),
            log: [], earlierLaunches: [(name: "KeyBridge 2026-10-02 09.00.00", text: "earlier\n")]
        )
        let text = report.text
        #expect(text.contains("## Recording\nStarted 2026-"))
        #expect(text.contains("; 1 presses (shortcuts only, never plain typing)\na line\n"))
        #expect(text.hasSuffix("## Earlier launches (1, last three days)\n### KeyBridge 2026-10-02 09.00.00\nearlier\n"))
    }
}
