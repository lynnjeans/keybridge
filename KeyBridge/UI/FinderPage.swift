import SwiftUI

/// Finder and the files around it (KB-218): the right-click menu, the path
/// box, and jumping open and save dialogs to where Finder is — what a
/// Windows user reaches for in Explorer and in Listary.
struct FinderPage: View {
    let rules: RulesController
    let pathBox: PathBoxController
    let locations: FileLocations
    /// Empties the recent folders, telling Finder's list apart from new ones.
    let clearHistory: () -> Void
    @State private var editing: Rule?
    @State private var confirmingClear = false

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
                        Text("In any app's open or save dialog, jump to the folder Finder is showing, or pick a favorite or recent folder, like Listary on Windows. The same entries are on the Shortcuts page.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    GroupSwitch(rules: rules, group: "dialogs", label: "Open & Save Dialogs")
                }
                Divider().padding(.top, 12)
                EntryList(rules: rules, group: "dialogs", edit: { editing = $0 })
                Divider()
                AdaptiveRow(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent folders in the list")
                        Text("Folders you open in Finder or go to with KeyBridge.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        Stepper(value: Binding(get: { locations.recentLimit }, set: { locations.recentLimit = $0 }),
                                in: FileLocations.limits) {
                            Text(locations.recentLimit, format: .number)
                                .monospacedDigit()
                        }
                        .fixedSize()
                        Button("Clear…") { confirmingClear = true }
                            .disabled(locations.history.isEmpty)
                    }
                }
                .padding(.vertical, 10)
                Divider()
                FavoritesEditor(locations: locations)
                    .padding(.top, 10)
            }
        }
        .sheet(item: $editing) { RuleEditor(rules: rules, rule: $0) }
        .confirmationDialog("Clear the recent folders?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive, action: clearHistory)
        } message: {
            Text("Favorites and Finder's own Recent Folders are kept.")
        }
    }
}

/// The favorite folders, listed first by the recent locations list: add with
/// a folder chooser, or with the star in the list itself; remove here.
private struct FavoritesEditor: View {
    let locations: FileLocations

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Favorites")
            if locations.favorites.isEmpty {
                Text("None yet. Add folders here, or press ⌘D on a folder in the list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(locations.favorites, id: \.self) { path in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(FileManager.default.displayName(atPath: path))
                                .lineLimit(1)
                            Text((path as NSString).abbreviatingWithTildeInPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Button {
                            locations.setFavorite(path, false)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from favorites")
                    }
                }
            }
            Button("Add Folder…", action: add)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { locations.setFavorite(url.path(percentEncoded: false).trimmingSlash, true) }
    }
}

private extension String {
    /// A folder URL's path ends in a slash; paths here are kept without one.
    var trimmingSlash: String {
        count > 1 && hasSuffix("/") ? String(dropLast()) : self
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
