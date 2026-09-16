import SwiftUI

/// The settings window: a sidebar of pages and the selected page beside it.
struct MainWindow: View {
    let engine: EngineController
    let onboarding: OnboardingController
    /// The preset and the user's changes to it, shown on the Shortcuts page.
    let rules: RulesController
    /// Remembered across launches, so the window reopens where it was left.
    @SceneStorage("mainWindow.page") private var page: Page = .overview

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $page)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            PageContent(page: page) {
                switch page {
                case .overview:
                    ModeCard(engine: engine)
                    PermissionsCard(permissions: engine.permissions, onboarding: onboarding)
                case .shortcuts:
                    ShortcutsPage(rules: rules)
                case .about:
                    AboutCard()
                default:
                    ComingSoon(page: page)
                }
            }
            .id(page)
        }
        .frame(minWidth: 780, minHeight: 520)
    }
}

/// A page's title and subtitle above its content, scrolling as one.
private struct PageContent<Content: View>: View {
    let page: Page
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.title)
                        .font(.largeTitle.bold())
                    Text(page.subtitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)
                content
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(page.title)
    }
}

/// The preset, group by group: a switch and an expander per group, each
/// entry as "what you press → what the Mac gets", and a search field.
private struct ShortcutsPage: View {
    let rules: RulesController
    @State private var search = ""
    @State private var expanded: Set<String> = ["editing"]
    /// The entry open in the editor sheet.
    @State private var editing: Rule?

    var body: some View {
        PresetBar(preset: rules.preset)

        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search shortcuts…", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.separator))

        ForEach(rules.preset.groups) { group in
            let matches = Self.matching(rules.rules(inGroup: group.id), search)
            // A search hides the groups it found nothing in, so what is left
            // on screen is only what matched.
            if search.isEmpty || !matches.isEmpty {
                GroupCard(
                    group: group,
                    entries: matches,
                    isOn: rules.isEnabled(group: group.id),
                    // While searching, matches stay open: collapsing them
                    // would hide the very thing that was looked for.
                    isExpanded: !search.isEmpty || expanded.contains(group.id),
                    canCollapse: search.isEmpty,
                    toggleExpanded: {
                        if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
                    },
                    setOn: { rules.setGroup(group.id, enabled: $0) },
                    isCustomized: rules.isCustomized,
                    edit: { editing = $0 }
                )
            }
        }

        Color.clear.frame(height: 0)
            .sheet(item: $editing) { rule in
                RuleEditor(rules: rules, rule: rule)
            }

        if !search.isEmpty && rules.preset.groups.allSatisfy({ Self.matching(rules.rules(inGroup: $0.id), search).isEmpty }) {
            ContentUnavailableView.search(text: search)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
    }

    /// Entries whose name, or either side of the mapping, contains the text.
    static func matching(_ rules: [Rule], _ search: String) -> [Rule] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return rules }
        return rules.filter { rule in
            var haystack = [RuleNames.name(of: rule), rule.id]
            if case .key(let combo) = rule.trigger { haystack += combo.caps(.windows) }
            if case .key(let combo) = rule.action { haystack += combo.caps(.mac) }
            return haystack.contains { $0.lowercased().contains(query) }
        }
    }
}

/// Which preset is in use. Switching between presets and re-applying one
/// arrive with the preset packs (KB-060) and the apply action (KB-061).
private struct PresetBar: View {
    let preset: Preset

    var body: some View {
        Card {
            HStack(spacing: 14) {
                IconTile(symbol: "list.bullet.rectangle", tint: .accentColor, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preset: \(RuleNames.presetName(preset.id))")
                        .font(.headline)
                    Text("^[\(preset.rules.count) mapping](inflect: true) in \(preset.groups.count) groups. More presets, and re-applying one, are still to come.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
        }
    }
}

/// One group: its switch, and its entries when expanded.
private struct GroupCard: View {
    let group: Preset.Group
    let entries: [Rule]
    let isOn: Bool
    let isExpanded: Bool
    let canCollapse: Bool
    let toggleExpanded: () -> Void
    let setOn: (Bool) -> Void
    let isCustomized: (String) -> Bool
    let edit: (Rule) -> Void

    var body: some View {
        Card {
            VStack(spacing: 0) {
                header
                if isExpanded {
                    Divider().padding(.top, 12)
                    entryList
                }
            }
        }
    }

    /// While a search narrows the group, the header says how much of it is
    /// showing, so the entries left out do not look lost.
    private var countText: LocalizedStringKey {
        entries.count < group.rules.count
            ? "\(entries.count) of ^[\(group.rules.count) mapping](inflect: true)"
            : "^[\(group.rules.count) mapping](inflect: true)"
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconTile(symbol: RuleNames.symbol(ofGroup: group.id), tint: RuleNames.tint(ofGroup: group.id), size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(RuleNames.name(ofGroup: group.id))
                    .font(.headline)
                Text(countText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { isOn }, set: setOn))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(RuleNames.name(ofGroup: group.id))
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .opacity(canCollapse ? 1 : 0.3)
        }
        // The whole header expands, except the switch itself.
        .contentShape(.rect)
        .onTapGesture { if canCollapse { toggleExpanded() } }
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, rule in
                if index > 0 { Divider() }
                EntryRow(rule: rule, isCustomized: isCustomized(rule.id)) { edit(rule) }
            }
        }
        // A switched-off group still shows what it would do, greyed out.
        .opacity(isOn ? 1 : 0.45)
    }
}

/// One entry of a group. Clicking it opens the editor.
private struct EntryRow: View {
    let rule: Rule
    let isCustomized: Bool
    let edit: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: edit) {
            HStack(alignment: .center, spacing: 12) {
                MappingView(rule: rule)
                    .opacity(rule.isEnabled ? 1 : 0.45)
                Spacer(minLength: 12)
                if isCustomized {
                    CustomizedBadge()
                }
                Text(RuleNames.name(of: rule))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .strikethrough(!rule.isEnabled)
                Image(systemName: "pencil")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityHint("Edit")
    }
}

/// Names for what the model only knows by identifier. The preset packs
/// (KB-060) will carry their own, and localization is KB-090.
enum RuleNames {
    static func presetName(_ id: String) -> String {
        id == "windows-standard" ? "Windows Standard" : id
    }

    static func name(ofGroup id: String) -> String {
        switch id {
        case "editing": "Editing"
        case "navigation": "Text Navigation"
        case "mouse": "Mouse"
        case "scroll": "Scroll"
        default: id
        }
    }

    static func symbol(ofGroup id: String) -> String {
        switch id {
        case "editing": "pencil"
        case "navigation": "arrow.left.and.right.text.vertical"
        case "mouse": "computermouse.fill"
        case "scroll": "arrow.up.and.down"
        default: "square.grid.2x2.fill"
        }
    }

    static func tint(ofGroup id: String) -> Color {
        switch id {
        case "editing": .indigo
        case "navigation": .teal
        case "mouse": .orange
        case "scroll": .cyan
        default: .gray
        }
    }

    static func name(of rule: Rule) -> String {
        let names = [
            "edit.copy": "Copy", "edit.cut": "Cut", "edit.paste": "Paste", "edit.undo": "Undo",
            "nav.lineStart": "Line start", "nav.lineEnd": "Line end",
            "nav.selectLineStart": "Select to line start", "nav.selectLineEnd": "Select to line end",
            "mouse.back": "Back", "mouse.forward": "Forward",
            "scroll.zoomIn": "Zoom in", "scroll.zoomOut": "Zoom out",
        ]
        return names[rule.id] ?? rule.id
    }
}

/// Stands in for a page that a later release fills in.
private struct ComingSoon: View {
    let page: Page

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Coming soon")
            } icon: {
                IconTile(symbol: page.symbol, tint: page.tint, size: 44)
            }
        } description: {
            Text("This page is not built yet. What KeyBridge does today is on the Overview.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// The app's version and license.
private struct AboutCard: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Card {
            HStack(spacing: 14) {
                IconTile(symbol: "command", tint: .accentColor, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("KeyBridge")
                        .font(.headline)
                    Text(version)
                        .foregroundStyle(.secondary)
                    Text("Built for people moving from Windows to the Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The master switch.
private struct ModeCard: View {
    let engine: EngineController

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Windows Shortcut Mode")
                        .font(.headline)
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                // Shown off while it cannot run, even if the user left it on;
                // it comes back on by itself once the permissions are granted.
                Toggle("Windows Shortcut Mode", isOn: Binding(
                    get: { engine.isEnabled && engine.canEnable },
                    set: { engine.isEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!engine.canEnable)
            }
        }
    }

    private var detail: String {
        if !engine.canEnable {
            return "Unavailable until KeyBridge has the permissions below. macOS does not let an app change shortcuts without them."
        }
        if !engine.isEnabled {
            return "Off. Every key, click and scroll reaches apps unchanged."
        }
        if !engine.isActive {
            return "On, but the event tap could not be started. Quitting and reopening KeyBridge may help."
        }
        return "On. Ctrl+C, Home/End, the mouse side buttons and fn+scroll work the Windows way."
    }
}

/// Whether KeyBridge has what it needs from macOS, and where to grant it.
private struct PermissionsCard: View {
    let permissions: PermissionMonitor
    let onboarding: OnboardingController

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Permissions")
                        .font(.headline)
                    Spacer()
                    if permissions.allGranted {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Action needed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.subheadline.weight(.semibold))

                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRow(permission: permission, granted: permissions.status(of: permission) == .granted)
                }

                // The guided way through, for anyone who closed it on the
                // first run or lost a permission later.
                if !permissions.allGranted {
                    Button("Set Up Permissions…") { onboarding.open() }
                }
            }
        }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let granted: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                Text(permission.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = permission.settingsHint(granted: granted) {
                    Text(hint)
                        .font(.caption)
                        // Secondary, not tertiary: tertiary is too faint to
                        // read in the dark appearance.
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if granted {
                Text("Granted")
                    .foregroundStyle(.secondary)
            } else {
                Button("Open Settings") {
                    NSWorkspace.shared.open(permission.settingsURL)
                }
            }
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
