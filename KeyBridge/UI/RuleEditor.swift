import AppKit
import SwiftUI

/// Edits one entry of the preset: what the user presses, what the Mac
/// receives, and whether the entry is on. Nothing is saved until Save, and
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
                LabeledContent("The Mac receives") {
                    action
                }
                Toggle("On", isOn: $draft.isEnabled)
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
        if case .key(let combo) = draft.trigger {
            RecorderField(combo: combo, style: .windows, isRecording: recording == .trigger,
                          liveModifiers: recorder.modifiers) {
                toggleRecording(.trigger)
            }
        } else {
            // Mouse buttons and scrolling cannot be recorded from the
            // keyboard; the Mouse and Scroll pages (KB-075) take them on.
            Text(triggerDescription).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var action: some View {
        if case .key(let combo) = draft.action {
            RecorderField(combo: combo, style: .mac, isRecording: recording == .action,
                          liveModifiers: recorder.modifiers) {
                toggleRecording(.action)
            }
        } else {
            Text("Not editable here").foregroundStyle(.secondary)
        }
    }

    private var triggerDescription: String {
        switch draft.trigger {
        case .key(let combo): combo.caps(.windows).joined(separator: "+")
        case .mouseButton(let number, let modifiers): (modifiers.caps(.windows) + ["Button \(number)"]).joined(separator: "+")
        case .scroll(let direction, let modifiers): (modifiers.caps(.windows) + ["Scroll \(direction.rawValue)"]).joined(separator: "+")
        }
    }

    private func toggleRecording(_ side: Side) {
        if recording == side {
            stopRecording()
            return
        }
        recording = side
        rules.isRecording = true
        recorder.start { combo in
            if let combo {
                switch side {
                case .trigger: draft.trigger = .key(combo: combo)
                case .action: draft.action = .key(combo: combo)
                }
            }
            stopRecording()
        }
    }

    private func stopRecording() {
        recorder.stop()
        recording = nil
        rules.isRecording = false
    }
}

/// A combination shown as keycaps; clicking it records a new one.
private struct RecorderField: View {
    let combo: KeyCombo
    let style: KeyStyle
    let isRecording: Bool
    let liveModifiers: Modifiers
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isRecording {
                    if liveModifiers.isEmpty {
                        Text("Press a shortcut…")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 3) {
                            ForEach(liveModifiers.caps(style), id: \.self) { Keycap(text: $0, isModifier: true) }
                        }
                    }
                } else {
                    KeyComboView(combo: combo, style: style)
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
        .help(isRecording ? "Press the new shortcut, or Esc to cancel" : "Click to record a new shortcut")
    }
}

/// Listens to key presses in KeyBridge's own windows and swallows them, so a
/// recorded ⌘W does not close the window.
///
/// Shortcuts the system keeps for itself, such as ⌘Tab or ⌘Space, never
/// reach an app and cannot be recorded this way.
@MainActor
@Observable
final class KeyRecorder {
    /// Modifiers held right now, shown while waiting for the key.
    private(set) var modifiers: Modifiers = []
    @ObservationIgnored private var monitor: Any?

    /// Calls `done` with the first combination pressed, or nil for Esc.
    func start(_ done: @escaping (KeyCombo?) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                modifiers = Modifiers(modifierFlags: event.modifierFlags)
                return event
            }
            guard !event.isARepeat else { return nil }
            let combo = KeyCombo(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
            done(combo == KeyCombo(.escape) ? nil : combo)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        modifiers = []
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
