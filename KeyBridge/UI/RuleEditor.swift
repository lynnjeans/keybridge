import AppKit
import SwiftUI

/// Edits one entry of the preset: what the user presses, and whether the
/// entry is on; for a mouse button, also what it does. Nothing is saved until Save, and
/// saving the preset's own version clears the customization.
struct RuleEditor: View {
    let rules: RulesController
    let original: Rule
    @State private var draft: Rule
    @State private var recording: Side?
    @State private var recorder = KeyRecorder()
    @Environment(\.dismiss) private var dismiss

    enum Side { case trigger, action }

    init(rules: RulesController, rule: Rule) {
        self.rules = rules
        original = rules.original(of: rule.id) ?? rule
        _draft = State(initialValue: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(RuleNames.name(of: draft))
                    .font(.title2.bold())
                if draft != original {
                    CustomizedBadge()
                }
            }

            Form {
                LabeledContent("When you press") {
                    trigger
                }
                LabeledContent("Does") {
                    action
                }
                Toggle("On", isOn: $draft.isEnabled)
                // The fn setting applies on top of what is recorded here.
                if rules.controlKey != .control, ControlKey.function.trigger(of: draft) != draft.trigger {
                    LabeledContent("") {
                        Text(rules.controlKey == .function ? "Pressed with fn instead of Ctrl" : "Also pressed with fn instead of Ctrl")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let note = scopeNote {
                    LabeledContent("Applies") {
                        Text(note).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.columns)

            if !conflicts.isEmpty {
                Label {
                    Text("Also used by \(conflicts.map(RuleNames.name(of:)).formatted()). Only one of them takes effect.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
                .font(.callout)
            }

            HStack {
                Button("Restore Default") {
                    stopRecording()
                    draft = original
                }
                .disabled(draft == original)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    rules.update(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(recording != nil)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onDisappear(perform: stopRecording)
    }

    private var conflicts: [Rule] {
        draft.isEnabled ? rules.conflicts(with: draft).filter(\.isEnabled) : []
    }

    /// Scopes are not editable yet; the editor only says what they are.
    private var scopeNote: String? {
        var note: String? = switch draft.scope.applications {
        case .all: nil
        case .except(let ids) where ids == BuiltInRules.terminals: "Everywhere except terminals"
        case .except: "Everywhere except some apps"
        case .only(let ids) where ids == [BuiltInRules.finderID]: "Only in Finder"
        case .only: "Only in some apps"
        }
        if draft.scope.skipsTextInput {
            note = (note ?? "Everywhere") + ", not while typing"
        }
        return note
    }

    @ViewBuilder private var trigger: some View {
        switch draft.trigger {
        case .key(let combo):
            RecorderField(isRecording: recording == .trigger, prompt: "Press a shortcut…",
                          liveModifiers: recorder.modifiers, style: .windows) {
                KeyComboView(combo: combo, style: .windows)
            } action: {
                toggleRecording(.trigger)
            }
        case .mouseButton(let number, let modifiers):
            RecorderField(isRecording: recording == .trigger, prompt: "Press a mouse button…",
                          liveModifiers: recorder.modifiers, style: .windows) {
                MouseButtonLabel(number: number, modifiers: modifiers)
            } action: {
                toggleRecording(.trigger)
            }
        case .scroll:
            Text("Set on the Scroll page").foregroundStyle(.secondary)
        }
    }

    /// What an entry does is what it is: Copy is ⌘C, and a Copy that sent
    /// something else would be misnamed. Only a mouse button, which means
    /// nothing by itself, is given a result of the user's choosing; any
    /// other mapping is a custom rule.
    private var resultIsEditable: Bool {
        if case .mouseButton = original.trigger { true } else { false }
    }

    @ViewBuilder private var action: some View {
        if !resultIsEditable {
            HStack(spacing: 8) {
                switch draft.action {
                case .key(let combo): KeyComboView(combo: combo, style: .mac)
                case .openApplication: EmptyView()
                }
                Text(RuleNames.name(of: draft))
                    .foregroundStyle(.secondary)
            }
        } else if case .key(let combo) = draft.action {
            RecorderField(isRecording: recording == .action, prompt: "Press a shortcut…",
                          liveModifiers: recorder.modifiers, style: .mac) {
                KeyComboView(combo: combo, style: .mac)
            } action: {
                toggleRecording(.action)
            }
        } else {
            Text("Not editable here").foregroundStyle(.secondary)
        }
    }

    private func toggleRecording(_ side: Side) {
        if recording == side {
            stopRecording()
            return
        }
        recording = side
        // A trigger keeps its kind: a mouse entry records mouse buttons, a
        // key entry key combinations. What the Mac receives is always keys.
        let wantsButton = side == .trigger && { if case .mouseButton = draft.trigger { true } else { false } }()
        recorder.start(rules: rules, accepting: { trigger in
            switch trigger {
            case .key: !wantsButton
            case .mouseButton: wantsButton
            case .scroll: false
            }
        }) { trigger in
            switch (side, trigger) {
            case (.trigger, let trigger?): draft.trigger = trigger
            case (.action, .key(let combo)?): draft.action = .key(combo: combo)
            default: break
            }
            stopRecording()
        }
    }

    private func stopRecording() {
        recorder.stop()
        recording = nil
    }
}

/// What a recorded trigger or result looks like; clicking it records a new
/// one.
private struct RecorderField<Content: View>: View {
    let isRecording: Bool
    let prompt: LocalizedStringKey
    let liveModifiers: Modifiers
    let style: KeyStyle
    @ViewBuilder let content: Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isRecording {
                    if liveModifiers.isEmpty {
                        Text(prompt)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 3) {
                            ForEach(liveModifiers.caps(style), id: \.self) { Keycap(text: $0, isModifier: true) }
                        }
                    }
                } else {
                    content
                }
                Spacer(minLength: 8)
                Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                    .foregroundStyle(isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            .frame(minHeight: 30)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: 220)
            .contentShape(.rect)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isRecording ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                            lineWidth: isRecording ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press the new one, or Esc to cancel" : "Click to record a new one")
    }
}

/// Records one trigger. While the engine runs, presses come from its event
/// tap, which sees them before the system does: fn+C or ⌘Space would
/// otherwise open Control Center or Spotlight instead of being recorded, and
/// a side button would go back in the browser. Without the tap, a monitor on
/// KeyBridge's own windows stands in.
///
/// Either way the press is swallowed, so a recorded ⌘W does not close the
/// window.
@MainActor
@Observable
final class KeyRecorder {
    /// Modifiers held right now, shown while waiting for the key.
    private(set) var modifiers: Modifiers = []
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private weak var rules: RulesController?

    /// The first of the two sources to deliver a press wins.
    private final class Once { var isDone = false }

    /// Calls `done` once, with the first accepted trigger, or nil for Esc.
    /// Presses that are not accepted are swallowed and ignored.
    func start(
        rules: RulesController,
        accepting accepts: @escaping @MainActor (Trigger) -> Bool,
        _ done: @escaping @MainActor (Trigger?) -> Void
    ) {
        stop()
        self.rules = rules
        let once = Once()
        let finish: @MainActor (Trigger) -> Void = { trigger in
            guard !once.isDone else { return }
            if trigger == .key(combo: KeyCombo(.escape)) {
                once.isDone = true
                done(nil)
            } else if accepts(trigger) {
                once.isDone = true
                done(trigger)
            }
        }
        rules.startRecording(finish)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .flagsChanged:
                modifiers = Modifiers(modifierFlags: event.modifierFlags)
                return event
            case .otherMouseDown:
                finish(.mouseButton(number: event.buttonNumber + 1,
                                    modifiers: Modifiers(modifierFlags: event.modifierFlags)))
                return nil
            default:
                if !event.isARepeat {
                    finish(.key(combo: KeyCombo(keyCode: event.keyCode, modifierFlags: event.modifierFlags)))
                }
                return nil
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        modifiers = []
        rules?.stopRecording()
        rules = nil
    }
}

/// A mouse button as a trigger: its modifiers, and the button by number.
struct MouseButtonLabel: View {
    let number: Int
    var modifiers: Modifiers = []

    var body: some View {
        HStack(spacing: 3) {
            ForEach(modifiers.caps(.windows), id: \.self) { Keycap(text: $0, isModifier: true) }
            Label("Button \(number)", systemImage: "computermouse")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Marks an entry the user has changed from the preset.
struct CustomizedBadge: View {
    var body: some View {
        Text("Customized")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}
