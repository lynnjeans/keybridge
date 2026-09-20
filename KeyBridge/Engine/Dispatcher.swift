import AppKit
import CoreGraphics
import OSLog

/// The path every event takes through KeyBridge: work out what it triggers,
/// find the rule that applies in the current context, and carry it out.
@MainActor
final class Dispatcher {
    // Carries a CGEvent, which is not Sendable; a disposition never leaves
    // the main thread, where the tap callback runs.
    enum Disposition: @unchecked Sendable {
        /// Let the original event continue to its destination.
        case passThrough
        /// Remove the original event.
        case consume
        /// Send this event on in place of the original.
        case replace(CGEvent)
    }

    /// The effective rules.
    var rules: [Rule] = [] {
        didSet { matcher = RuleMatcher(rules: rules) }
    }

    private var matcher = RuleMatcher(rules: [])

    /// Which way mouse wheels scroll.
    var wheelDirection = WheelDirection.system
    private let frontmostBundleID: @MainActor () -> String?
    private let isEditingText: @MainActor () -> Bool

    /// Keys whose press was remapped and that are still held. Their repeats
    /// and release are rewritten to match the press, whatever modifiers are
    /// held by then: the user may let go of Ctrl before C.
    private var heldKeys: [KeyCode: HeldKey] = [:]

    private struct HeldKey {
        let ruleID: String
        /// What the press became; nil when the action was not a keystroke, in
        /// which case repeats and the release are swallowed.
        let output: KeyCombo?
    }

    /// Mouse buttons whose press was turned into an action and that are still
    /// held. Their release is swallowed too, so applications never see half
    /// a click.
    private var heldButtons: Set<Int> = []

    private var scrollStepper = ScrollStepper()

    /// Sends events that are not replacements, such as the keystroke a side
    /// button stands for. Replaceable so tests can capture them instead.
    private let post: @MainActor (CGEvent) -> Void

    /// Launches or brings forward an application, for rules that open one.
    /// Replaceable so tests do not start real apps.
    private let openApplication: @MainActor (String) -> Void

    /// The user's shortcuts for system functions. Replaceable so tests do not
    /// depend on this Mac's settings.
    private let systemShortcuts: @MainActor () -> SymbolicHotKeys
    /// Moves the frontmost window. Injected so tests need no real windows.
    private let snap: @MainActor (WindowAction) -> Void

    init(
        frontmostBundleID: @escaping @MainActor () -> String?,
        isEditingText: @escaping @MainActor () -> Bool = { false },
        post: @escaping @MainActor (CGEvent) -> Void = { SyntheticEvent.post($0) },
        openApplication: @escaping @MainActor (String) -> Void = { Dispatcher.launch($0) },
        systemShortcuts: @escaping @MainActor () -> SymbolicHotKeys = { SymbolicHotKeys.current() },
        snap: @escaping @MainActor (WindowAction) -> Void = { WindowElement.perform($0) }
    ) {
        self.frontmostBundleID = frontmostBundleID
        self.isEditingText = isEditingText
        self.post = post
        self.openApplication = openApplication
        self.systemShortcuts = systemShortcuts
        self.snap = snap
    }

    /// While set, the rule editor is recording a trigger: key presses and
    /// extra mouse buttons are handed here and swallowed instead of being
    /// matched. Reading them this early catches combinations the system
    /// would take for itself before they reach any window, such as fn+C
    /// opening Control Center.
    var recorder: (@MainActor (Trigger) -> Void)?

    /// Buttons pressed while recording, whose release is swallowed too.
    private var recordedButtons: Set<Int> = []

    /// Sees every left button press and release, which always go on
    /// unchanged: clicking the frontmost app's Dock icon minimizes its window
    /// (`DockClick`).
    var leftMouse: (@MainActor (CGEvent, CGEventType) -> Void)?

    func process(_ event: CGEvent, type: CGEventType) -> Disposition {
        if let recorder, let disposition = record(event, type: type, into: recorder) {
            return disposition
        }
        // Recording can end while the recorded button is still down.
        if type == .otherMouseUp, recordedButtons.remove(event.mouseButtonNumber) != nil {
            return .consume
        }
        switch type {
        case .keyDown:
            return keyDown(event)
        case .keyUp:
            return keyUp(event)
        case .otherMouseDown:
            return mouseDown(event)
        case .otherMouseUp:
            return heldButtons.remove(event.mouseButtonNumber) == nil ? .passThrough : .consume
        case .scrollWheel:
            return scroll(event)
        case .leftMouseDown, .leftMouseUp:
            leftMouse?(event, type)
            return .passThrough
        default:
            return .passThrough
        }
    }

    private func record(_ event: CGEvent, type: CGEventType, into recorder: @MainActor (Trigger) -> Void) -> Disposition? {
        switch type {
        case .keyDown:
            if !event.isAutorepeat, let trigger = Trigger(event: event, type: type) {
                recorder(trigger)
            }
            return .consume
        case .keyUp:
            // The release of a key remapped before recording began still has
            // to go out, or its replacement would stay pressed.
            return heldKeys[event.keyCode] == nil ? .consume : nil
        case .otherMouseDown:
            if let trigger = Trigger(event: event, type: type) {
                recordedButtons.insert(event.mouseButtonNumber)
                recorder(trigger)
            }
            return .consume
        default:
            return nil
        }
    }

    /// Releases every remapped key still held, so nothing is left pressed
    /// when the tap stops in the middle of a keystroke.
    func releaseHeldKeys() {
        for held in heldKeys.values {
            if let output = held.output, let release = SyntheticEvent.key(output, down: false) {
                post(release)
            }
        }
        heldKeys = [:]
        heldButtons = []
    }

    /// A mouse button press triggers its action once, as a complete
    /// keystroke; holding the button does not repeat it.
    private func mouseDown(_ event: CGEvent) -> Disposition {
        guard let rule = match(event, type: .otherMouseDown) else { return .passThrough }
        record(rule)
        heldButtons.insert(event.mouseButtonNumber)
        carryOut(rule.action)
        return .consume
    }

    /// A matched scroll never reaches the application: while the modifier is
    /// held, the page should zoom, not also scroll. The action fires once per
    /// wheel notch, as the stepper decides.
    private func scroll(_ event: CGEvent) -> Disposition {
        guard let rule = match(event, type: .scrollWheel), let direction = event.scrollDirection else {
            // Not a rule's, so plain scrolling: the wheel's direction applies.
            // The event is changed in place and goes on.
            if wheelDirection.reverses(source: event.scrollSource, isNatural: event.isNaturalScrolling) {
                event.reverseScroll()
            }
            return .passThrough
        }
        record(rule)
        if scrollStepper.step(
            direction: direction, source: event.scrollSource,
            lines: event.scrollLines, timestamp: event.timestamp
        ) {
            carryOut(rule.action)
        }
        return .consume
    }

    /// Carries out an action triggered by something other than a key, so
    /// there is no original event to replace: a keystroke is posted as a
    /// complete press and release.
    private func carryOut(_ action: Action) {
        switch action {
        case .key(let combo):
            for down in [true, false] {
                if let keystroke = SyntheticEvent.key(combo, down: down) { post(keystroke) }
            }
        case .openApplication(let bundleID):
            openApplication(bundleID)
        case .systemAction(let function):
            trigger(function)
        case .windowAction(let position):
            move(position)
        }
    }

    /// Posts the user's shortcut for a system function, or opens the app that
    /// does the same when it has none. Nothing else is posted for a function
    /// switched off with no app to stand in; the rule editor says so.
    ///
    /// The shortcut is read after the tap callback returns, since reading
    /// another app's preferences can take a moment.
    private func trigger(_ function: SystemAction) {
        DispatchQueue.main.async { [self] in
            switch systemShortcuts().shortcut(for: function) {
            case .combo(let combo):
                for down in [true, false] {
                    if let keystroke = SyntheticEvent.key(combo, down: down) { post(keystroke) }
                }
            case .off, .none:
                if let bundleID = function.fallbackApplication {
                    openApplication(bundleID)
                } else {
                    Logger.engine.notice("\(function.rawValue, privacy: .public) has no shortcut in System Settings; nothing posted")
                }
            }
        }
    }

    /// Snaps the frontmost window, after the tap callback returns: the
    /// Accessibility round trip to another app is far too slow to hold up the
    /// event stream, and a held key must not stall the keyboard.
    private func move(_ position: WindowAction) {
        DispatchQueue.main.async { [self] in snap(position) }
    }

    private func keyDown(_ event: CGEvent) -> Disposition {
        let key = event.keyCode
        let rule = match(event, type: .keyDown)

        if let held = heldKeys[key] {
            // Auto-repeat of a remapped key. If the modifiers changed mid-hold
            // the combination no longer applies; swallowing the rest of the
            // repeats beats suddenly typing the plain key.
            guard rule?.id == held.ruleID, let output = held.output else { return .consume }
            return replacement(output, down: true, for: event)
        }

        // A repeat that matches only now, because a modifier was pressed while
        // the key was already held, belongs to a press that went out unchanged.
        guard let rule, !event.isAutorepeat else { return .passThrough }
        record(rule)

        switch rule.action {
        case .key(let combo):
            heldKeys[key] = HeldKey(ruleID: rule.id, output: combo)
            return replacement(combo, down: true, for: event)
        case .openApplication(let bundleID):
            heldKeys[key] = HeldKey(ruleID: rule.id, output: nil)
            openApplication(bundleID)
            return .consume
        case .systemAction(let function):
            heldKeys[key] = HeldKey(ruleID: rule.id, output: nil)
            trigger(function)
            return .consume
        case .windowAction(let position):
            heldKeys[key] = HeldKey(ruleID: rule.id, output: nil)
            move(position)
            return .consume
        }
    }

    private func keyUp(_ event: CGEvent) -> Disposition {
        guard let held = heldKeys.removeValue(forKey: event.keyCode) else { return .passThrough }
        guard let output = held.output else { return .consume }
        return replacement(output, down: false, for: event)
    }

    private func replacement(_ combo: KeyCombo, down: Bool, for original: CGEvent) -> Disposition {
        guard let event = SyntheticEvent.key(combo, down: down, replacing: original) else {
            Logger.engine.error("Could not create a replacement key event")
            return .passThrough
        }
        return .replace(event)
    }

    private func match(_ event: CGEvent, type: CGEventType) -> Rule? {
        guard let trigger = Trigger(event: event, type: type) else { return nil }
        return matcher.match(
            trigger, in: MatchContext(frontmostBundleID: frontmostBundleID()), isEditingText: isEditingText
        )
    }

    private static func launch(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Logger.engine.error("No application with bundle identifier \(bundleID, privacy: .public)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func record(_ rule: Rule) {
        #if DEBUG
        matchCounts[rule.id, default: 0] += 1
        #endif
    }

    #if DEBUG
    /// KB_DEBUG_SYSACTION: triggers a system function as a rule would.
    func selfTestTrigger(_ function: SystemAction) {
        trigger(function)
    }

    /// How often each rule matched since the last call. Rule IDs are part of
    /// KeyBridge's configuration, not user input, so they are safe to log.
    private var matchCounts: [String: Int] = [:]

    func takeMatchCounts() -> [String: Int] {
        defer { matchCounts = [:] }
        return matchCounts
    }
    #endif
}

extension Logger {
    static let engine = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeyBridge",
        category: "engine"
    )
}
