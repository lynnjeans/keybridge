import SwiftUI

/// Finder and the files around it (KB-218): the right-click menu, the path
/// box, and jumping open and save dialogs to where Finder is — what a
/// Windows user reaches for in Explorer and in Listary.
struct FinderPage: View {
    let rules: RulesController
    let pathBox: PathBoxController
    @State private var editing: Rule?

    var body: some View {
        FinderMenuCard()
        PathBoxCard(pathBox: pathBox, rules: rules)
        Card {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    IconTile(symbol: RuleNames.symbol(ofGroup: "dialogs"), tint: RuleNames.tint(ofGroup: "dialogs"), size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open & Save Dialogs")
                            .font(.headline)
                        Text("In any app's open or save dialog, jump to the folder Finder is showing, like Listary on Windows. The same entries are on the Shortcuts page.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    GroupSwitch(rules: rules, group: "dialogs", label: "Open & Save Dialogs")
                }
                Divider().padding(.top, 12)
                EntryList(rules: rules, group: "dialogs", edit: { editing = $0 })
            }
        }
        .sheet(item: $editing) { RuleEditor(rules: rules, rule: $0) }
    }
}

/// The shortcut that shows the paste-a-path box over Finder (KB-213).
private struct PathBoxCard: View {
    let pathBox: PathBoxController
    let rules: RulesController
    @State private var recorder = KeyRecorder()
    @State private var isRecording = false

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: "signpost.right.fill", tint: .teal, size: 30)
                VStack(alignment: .leading, spacing: 8) {
                    AdaptiveRow(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paste a path in Finder")
                                .font(.headline)
                            Text("Only while Finder is in front: paste or type a path, Return to jump. Click to record a different shortcut.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 12) {
                            RecorderField(isRecording: isRecording, prompt: "Press a shortcut…",
                                          liveModifiers: recorder.modifiers, style: .mac) {
                                KeyComboView(combo: pathBox.hotKey, style: .mac)
                            } action: {
                                isRecording ? stop() : start()
                            }
                            Toggle("Paste a path in Finder", isOn: Binding(
                                get: { pathBox.isEnabled },
                                set: { pathBox.isEnabled = $0 }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                    }
                    if let problem = pathBox.hotKeyProblem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    } else if let conflict {
                        Label("\(conflict) also uses this shortcut; the path box takes it in Finder.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .onDisappear { if isRecording { stop() } }
    }

    /// A KeyBridge rule with the same trigger, which the box would shadow
    /// while Finder is in front.
    private var conflict: String? {
        rules.effectiveRules.first { $0.isEnabled && $0.trigger == .key(combo: pathBox.hotKey) }
            .map { $0.name ?? RuleNames.name(of: $0) }
    }

    private func start() {
        isRecording = true
        pathBox.suspendHotKey()
        recorder.start(rules: rules, accepting: { if case .key = $0 { true } else { false } }) { trigger in
            if case .key(let combo)? = trigger { pathBox.setHotKey(combo) }
            stop()
        }
    }

    private func stop() {
        recorder.stop()
        isRecording = false
        pathBox.resumeHotKey()
    }
}
