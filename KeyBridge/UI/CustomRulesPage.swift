import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Rules of the user's own: any key combination or mouse button to any key
/// combination or app, anywhere or only in some apps.
struct CustomRulesPage: View {
    let rules: RulesController
    /// The rule open in the editor; a new one has no ID in the configuration
    /// yet.
    @State private var editing: EditedRule?

    struct EditedRule: Identifiable {
        let rule: Rule?
        let id = UUID()
    }

    var body: some View {
        Group {
            if rules.customRules.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No custom rules yet")
                        .font(.headline)
                    Text("Map any key combination or mouse button to another shortcut or to an app — for example fn+C to ⌘C next to Ctrl+C, or Win+E to Finder.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("New Rule…") { editing = EditedRule(rule: nil) }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                AdaptiveRow {
                    Text("Your rules come before the preset: where both use the same shortcut, yours wins.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("New Rule…") { editing = EditedRule(rule: nil) }
                }
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(rules.customRules.enumerated()), id: \.element.id) { index, rule in
                            if index > 0 { Divider() }
                            CustomRuleRow(rules: rules, rule: rule) { editing = EditedRule(rule: rule) }
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { CustomRuleEditor(rules: rules, existing: $0.rule) }
    }
}

private struct CustomRuleRow: View {
    let rules: RulesController
    let rule: Rule
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: edit) {
                AdaptiveRow(flexible: .trailing, minFlexibleWidth: 100, stackedSpacing: 6) {
                    MappingView(rule: rule)
                        .opacity(rule.isEnabled ? 1 : 0.45)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let name = rule.name, !name.isEmpty {
                            Text(name).font(.callout)
                        }
                        Text(ScopeText.describe(rule.scope.applications))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Toggle("On", isOn: Binding(
                get: { rule.isEnabled },
                set: { var changed = rule; changed.isEnabled = $0; rules.saveCustomRule(changed) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Delete", role: .destructive) { rules.deleteCustomRule(rule.id) }
        }
    }
}

/// Which apps a rule applies in, in words.
enum ScopeText {
    static func describe(_ filter: ApplicationFilter) -> String {
        switch filter {
        case .all: String(localized: "Everywhere")
        case .only(let ids): String(localized: "Only in \(names(ids))")
        case .except(let ids) where ids == BuiltInRules.terminals: String(localized: "Everywhere except terminals")
        case .except(let ids): String(localized: "Everywhere except \(names(ids))")
        }
    }

    static func names(_ ids: [String]) -> String {
        ids.map(appName).formatted()
    }

    /// The app's name as the user knows it, or its identifier when it is not
    /// installed.
    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Creates or edits a custom rule. Nothing is saved until Save.
struct CustomRuleEditor: View {
    let rules: RulesController
    let existing: Rule?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var trigger: Trigger?
    @State private var result: Result
    @State private var systemAction: SystemAction = .missionControl
    @State private var combo: KeyCombo?
    @State private var app: String?
    @State private var where_: Where
    @State private var apps: [String]
    @State private var isEnabled: Bool
    @State private var recording: Side?
    @State private var recorder = KeyRecorder()
    @State private var confirmingDelete = false

    enum Side { case trigger, action }
    enum Result: Hashable { case keys, app, system }
    enum Where: Hashable { case everywhere, only, except }

    init(rules: RulesController, existing: Rule?) {
        self.rules = rules
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _trigger = State(initialValue: existing?.trigger)
        _isEnabled = State(initialValue: existing?.isEnabled ?? true)
        switch existing?.action {
        case .openApplication(let bundleID)?:
            _result = State(initialValue: .app)
            _app = State(initialValue: bundleID)
            _combo = State(initialValue: nil)
        case .systemAction(let function)?:
            _result = State(initialValue: .system)
            _systemAction = State(initialValue: function)
            _combo = State(initialValue: nil)
            _app = State(initialValue: nil)
        case .key(let combo)?:
            _result = State(initialValue: .keys)
            _combo = State(initialValue: combo)
            _app = State(initialValue: nil)
        case nil:
            _result = State(initialValue: .keys)
            _combo = State(initialValue: nil)
            _app = State(initialValue: nil)
        }
        switch existing?.scope.applications ?? .all {
        case .all:
            _where_ = State(initialValue: .everywhere)
            _apps = State(initialValue: [])
        case .only(let ids):
            _where_ = State(initialValue: .only)
            _apps = State(initialValue: ids)
        case .except(let ids):
            _where_ = State(initialValue: .except)
            _apps = State(initialValue: ids)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(existing == nil ? "New Rule" : "Edit Rule")
                .font(.title2.bold())

            Form {
                TextField("Name", text: $name, prompt: Text("Optional"))
                LabeledContent("When you press") {
                    RecorderField(isRecording: recording == .trigger, prompt: "Press keys or a mouse button…",
                                  liveModifiers: recorder.modifiers, style: .windows) {
                        switch trigger {
                        case .key(let combo)?: KeyComboView(combo: combo, style: .windows)
                        case .mouseButton(let number, let modifiers)?: MouseButtonLabel(number: number, modifiers: modifiers)
                        default: Text("Click to record").foregroundStyle(.secondary)
                        }
                    } action: {
                        toggleRecording(.trigger)
                    }
                }
                Picker("Does", selection: $result) {
                    Text("A shortcut").tag(Result.keys)
                    Text("Open an app").tag(Result.app)
                    Text("System function").tag(Result.system)
                }
                .pickerStyle(.segmented)
                LabeledContent("") {
                    if result == .keys {
                        RecorderField(isRecording: recording == .action, prompt: "Press a shortcut…",
                                      liveModifiers: recorder.modifiers, style: .mac) {
                            if let combo {
                                KeyComboView(combo: combo, style: .mac)
                            } else {
                                Text("Click to record").foregroundStyle(.secondary)
                            }
                        } action: {
                            toggleRecording(.action)
                        }
                    } else if result == .system {
                        SystemActionPicker(selection: $systemAction)
                    } else {
                        HStack {
                            if let app { AppLabel(bundleID: app) }
                            Button(app == nil ? "Choose App…" : "Change…") {
                                if let chosen = AppChooser.choose() { app = chosen }
                            }
                        }
                    }
                }
                Picker("Applies", selection: $where_) {
                    Text("Everywhere").tag(Where.everywhere)
                    Text("Only in these apps").tag(Where.only)
                    Text("Everywhere except").tag(Where.except)
                }
                if where_ != .everywhere {
                    LabeledContent("") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(apps, id: \.self) { id in
                                HStack {
                                    AppLabel(bundleID: id)
                                    Spacer()
                                    Button {
                                        apps.removeAll { $0 == id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Button("Add App…") {
                                if let chosen = AppChooser.choose(), !apps.contains(chosen) { apps.append(chosen) }
                            }
                        }
                        .frame(width: 220, alignment: .leading)
                    }
                }
                Toggle("On", isOn: $isEnabled)
            }
            .formStyle(.columns)

            if let draft, !conflicts(of: draft).isEmpty {
                Label {
                    Text("Takes the place of \(conflicts(of: draft).map(RuleNames.name(of:)).formatted()) where both apply.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
                .font(.callout)
            }

            HStack {
                if existing != nil {
                    Button("Delete Rule", role: .destructive) { confirmingDelete = true }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let draft { rules.saveCustomRule(draft) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft == nil || recording != nil)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onDisappear(perform: stopRecording)
        .confirmationDialog("Delete this rule?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                if let existing { rules.deleteCustomRule(existing.id) }
                dismiss()
            }
        }
    }

    /// The rule as edited, or nil while something it needs is missing.
    private var draft: Rule? {
        guard let trigger else { return nil }
        let action: Action
        switch result {
        case .keys:
            guard let combo else { return nil }
            action = .key(combo: combo)
        case .app:
            guard let app else { return nil }
            action = .openApplication(bundleID: app)
        case .system:
            action = .systemAction(systemAction)
        }
        let applications: ApplicationFilter
        switch where_ {
        case .everywhere: applications = .all
        case .only:
            guard !apps.isEmpty else { return nil }
            applications = .only(bundleIDs: apps)
        case .except:
            applications = apps.isEmpty ? .all : .except(bundleIDs: apps)
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return Rule(
            id: existing?.id ?? "custom.\(UUID().uuidString)",
            trigger: trigger, action: action,
            scope: Scope(applications: applications),
            isEnabled: isEnabled,
            name: trimmed.isEmpty ? nil : trimmed
        )
    }

    /// Preset rules this one overrides: same trigger, where both apply.
    private func conflicts(of draft: Rule) -> [Rule] {
        guard draft.isEnabled else { return [] }
        return rules.effectiveRules.filter {
            $0.id != draft.id && $0.isEnabled && $0.trigger == draft.trigger && !$0.id.hasPrefix("custom.")
        }
    }

    private func toggleRecording(_ side: Side) {
        if recording == side {
            stopRecording()
            return
        }
        recording = side
        recorder.start(rules: rules, accepting: { trigger in
            switch trigger {
            case .key: true
            case .mouseButton: side == .trigger
            case .scroll: false
            }
        }) { recorded in
            switch (side, recorded) {
            case (.trigger, let recorded?): trigger = recorded
            case (.action, .key(let recorded)?): combo = recorded
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

/// Asks for an app in the Applications folder and returns its identifier.
enum AppChooser {
    @MainActor
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}

/// An app's icon and name.
struct AppLabel: View {
    let bundleID: String

    var body: some View {
        HStack(spacing: 6) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(ScopeText.appName(bundleID))
        }
    }
}
