import AppKit
import SwiftUI

/// The settings window: a sidebar of pages and the selected page beside it.
struct MainWindow: View {
    let engine: EngineController
    let onboarding: OnboardingController
    /// The preset and the user's changes to it, shown on the Shortcuts page.
    let rules: RulesController
    let secureInput: SecureInputMonitor
    let otherRemappers: OtherRemapperMonitor
    let clipboard: ClipboardController
    let pathBox: PathBoxController
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
                    OverviewPage(engine: engine, onboarding: onboarding, rules: rules, secureInput: secureInput,
                                 otherRemappers: otherRemappers) { page = $0 }
                case .shortcuts:
                    ShortcutsPage(rules: rules)
                case .mouse:
                    MousePage(rules: rules)
                case .scroll:
                    ScrollPage(rules: rules)
                case .clipboard:
                    ClipboardPage(clipboard: clipboard, rules: rules)
                case .finder:
                    FinderPage(rules: rules, pathBox: pathBox)
                case .customRules:
                    CustomRulesPage(rules: rules)
                case .about:
                    AboutCard()
                    LegalCard()
                    DiagnosticsCard {
                        await DiagnosticReport.collect(engine: engine, rules: rules, secureInput: secureInput,
                                                 otherRemappers: otherRemappers, clipboard: clipboard)
                    }
                default:
                    ComingSoon(page: page)
                }
            }
            .id(page)
        }
        .frame(minWidth: 780, minHeight: 520)
        .showsInDock()
        #if DEBUG
        .onAppear { if let requested = LayoutCheck.page { page = requested } }
        #endif
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
    @State private var expanded: Set<String> = Self.initiallyExpanded
    /// The entry open in the editor sheet.
    @State private var editing: Rule?
    @State private var confirmingWinKey = false

    var body: some View {
        PresetBar(rules: rules, groups: Self.groups(of: rules.preset))
        ControlKeyCard(choice: Binding(get: { rules.controlKey }, set: { rules.setControlKey($0) }))

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

        ForEach(Self.groups(of: rules.preset)) { group in
            let matches = Self.matching(rules.rules(inGroup: group.id), search, rules.controlKey)
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
                    setOn: { isOn in
                        if isOn && group.id == "winKey" {
                            confirmingWinKey = true
                        } else {
                            rules.setGroup(group.id, enabled: isOn)
                        }
                    },
                    isCustomized: rules.isCustomized,
                    displayTrigger: rules.controlKey.trigger(of:),
                    edit: { editing = $0 }
                )
            }
        }

        Color.clear.frame(height: 0)
            .sheet(item: $editing) { rule in
                RuleEditor(rules: rules, rule: rule)
            }
            .alert("Turn on Windows key shortcuts?", isPresented: $confirmingWinKey) {
                Button("Turn On") { rules.setGroup("winKey", enabled: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A PC keyboard's Windows key reaches the Mac as ⌘, so these shortcuts also replace ⌘L, ⌘E, ⌘D, ⌘. and ⌘⇧S on a Mac keyboard. Leave this off if you use a Mac keyboard.")
            }

        if !search.isEmpty && Self.groups(of: rules.preset).allSatisfy({ Self.matching(rules.rules(inGroup: $0.id), search, rules.controlKey).isEmpty }) {
            ContentUnavailableView.search(text: search)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
    }

    private static var initiallyExpanded: Set<String> {
        #if DEBUG
        if LayoutCheck.expandsAllGroups { return Set(BuiltInRules.preset.groups.map(\.id)) }
        #endif
        return ["editing"]
    }

    /// The keyboard groups; mouse buttons and scrolling have pages of their
    /// own.
    static func groups(of preset: Preset) -> [Preset.Group] {
        preset.groups.filter { !["mouse", "scroll"].contains($0.id) }
    }

    /// Entries whose name, or either side of the mapping, contains the text.
    static func matching(_ rules: [Rule], _ search: String, _ controlKey: ControlKey) -> [Rule] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return rules }
        return rules.filter { rule in
            var haystack = [RuleNames.name(of: rule), rule.id]
            if case .key(let combo) = controlKey.trigger(of: rule) { haystack += combo.caps(.windows) }
            if case .key(let combo) = rule.action { haystack += combo.caps(.mac) }
            if case .systemAction(let function) = rule.action { haystack.append(function.name) }
            return haystack.contains { $0.lowercased().contains(query) }
        }
    }
}

/// Which preset is in use. Switching between presets and re-applying one
/// arrive with the preset packs (KB-060) and the apply action (KB-061).
private struct PresetBar: View {
    let rules: RulesController
    let groups: [Preset.Group]
    private var preset: Preset { rules.preset }

    var body: some View {
        Card {
            HStack(spacing: 14) {
                IconTile(symbol: "list.bullet.rectangle", tint: .accentColor, size: 34)
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preset: \(RuleNames.presetName(preset.id))")
                            .font(.headline)
                        Text("^[\(groups.flatMap(\.rules).count) shortcut](inflect: true) in \(groups.count) groups; mouse and scroll are on their own pages.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    RestoreDefaultsButton(rules: rules)
                }
            }
        }
    }
}

/// Which key the Ctrl shortcuts are pressed with.
private struct ControlKeyCard: View {
    @Binding var choice: ControlKey

    var body: some View {
        Card {
            HStack(spacing: 14) {
                IconTile(symbol: "globe", tint: .indigo, size: 34)
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Press Ctrl shortcuts with")
                            .font(.headline)
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // In the order the keys sit on a Mac keyboard: fn, then Ctrl.
                    Picker("Press Ctrl shortcuts with", selection: $choice) {
                        Text("fn").tag(ControlKey.function)
                        Text("Ctrl").tag(ControlKey.control)
                        Text("Both").tag(ControlKey.both)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    /// fn+← reaches the Mac as Home, so fn cannot stand in for Ctrl there.
    private static let arrowNote = String(localized: "Word moves stay Ctrl+← / →, since fn+← is Home on a Mac keyboard.")

    private var description: LocalizedStringKey {
        switch choice {
        case .control: "Ctrl+C copies, as on Windows."
        case .function: "fn+C copies, also in terminals. Ctrl keeps its Mac meaning, and fn takes the place of its 🌐 shortcuts. \(Self.arrowNote)"
        case .both: "Ctrl+C and fn+C both copy. In terminals only fn does. \(Self.arrowNote)"
        }
    }
}

/// One group: its switch, and its entries when expanded.
struct GroupCard: View {
    let group: Preset.Group
    let entries: [Rule]
    let isOn: Bool
    let isExpanded: Bool
    let canCollapse: Bool
    let toggleExpanded: () -> Void
    let setOn: (Bool) -> Void
    let isCustomized: (String) -> Bool
    /// The trigger as the user presses it, which differs from the rule's
    /// when fn stands in for Ctrl.
    let displayTrigger: (Rule) -> Trigger
    let edit: (Rule) -> Void

    var body: some View {
        Card {
            VStack(spacing: 0) {
                header
                if isExpanded {
                    Divider().padding(.top, 12)
                    entryList
                    if group.id == "system" {
                        Divider()
                        FunctionKeysRow()
                    }
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
                if let note = RuleNames.note(ofGroup: group.id) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                EntryRow(rule: rule, trigger: displayTrigger(rule), isCustomized: isCustomized(rule.id)) { edit(rule) }
            }
        }
        // A switched-off group still shows what it would do, greyed out.
        .opacity(isOn ? 1 : 0.45)
    }
}

/// F1–F12 as standard function keys is a system setting, not a mapping: an
/// Apple keyboard's top row sends brightness and volume events, not F-keys.
private struct FunctionKeysRow: View {
    var body: some View {
        AdaptiveRow {
            VStack(alignment: .leading, spacing: 2) {
                Text("F1–F12 as standard function keys")
                Text("Set in System Settings › Keyboard › Keyboard Shortcuts › Function Keys. A PC keyboard's F-keys already work.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Keyboard Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.vertical, 9)
    }
}

/// One entry of a group. Clicking it opens the editor.
struct EntryRow: View {
    let rule: Rule
    let trigger: Trigger
    let isCustomized: Bool
    let edit: () -> Void
    @State private var isHovered = false

    private var displayed: Rule {
        var rule = rule
        rule.trigger = trigger
        return rule
    }

    var body: some View {
        Button(action: edit) {
            // A long name goes under the keys rather than being squeezed
            // beside them.
            AdaptiveRow(flexible: .trailing, minFlexibleWidth: 100, stackedSpacing: 6) {
                MappingView(rule: displayed)
                    .opacity(rule.isEnabled ? 1 : 0.45)
                HStack(spacing: 12) {
                    if isCustomized {
                        CustomizedBadge()
                    }
                    Text(RuleNames.name(of: rule))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .strikethrough(!rule.isEnabled)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "pencil")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .opacity(isHovered ? 1 : 0)
                }
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
        id == "windows-standard" ? String(localized: "Windows Standard") : id
    }

    static func name(ofGroup id: String) -> String {
        switch id {
        case "editing": String(localized: "Editing")
        case "navigation": String(localized: "Text Navigation")
        case "finder": String(localized: "File Management")
        case "dialogs": String(localized: "Open & Save Dialogs")
        case "windows": String(localized: "Apps & System")
        case "browser": String(localized: "Browser")
        case "system": String(localized: "System")
        case "winKey": String(localized: "Windows Key")
        case "mouse": String(localized: "Mouse")
        case "scroll": String(localized: "Scroll")
        case "window": String(localized: "Window Snapping")
        default: id
        }
    }

    /// A line under the group's name, for groups that need explaining.
    static func note(ofGroup id: String) -> String? {
        switch id {
        case "finder": String(localized: "Only in Finder, and not while renaming or searching")
        case "dialogs": String(localized: "Only while an open or save dialog is in front, like Listary on Windows")
        case "winKey": String(localized: "Off by default: also takes over ⌘ shortcuts on a Mac keyboard")
        case "window": String(localized: "⌥ sits where the Windows key does, so ⌥ and an arrow places or minimizes the window in front")
        default: nil
        }
    }

    static func symbol(ofGroup id: String) -> String {
        switch id {
        case "editing": "pencil"
        case "navigation": "arrow.left.and.right.text.vertical"
        case "finder": "folder.fill"
        case "dialogs": "folder.badge.gearshape"
        case "windows": "macwindow.on.rectangle"
        case "browser": "globe"
        case "system": "gearshape.fill"
        case "winKey": "command"
        case "mouse": "computermouse.fill"
        case "scroll": "arrow.up.and.down"
        case "window": "rectangle.split.2x1"
        default: "square.grid.2x2.fill"
        }
    }

    static func tint(ofGroup id: String) -> Color {
        switch id {
        case "editing": .indigo
        case "navigation": .teal
        case "finder": .blue
        case "dialogs": .brown
        case "windows": .purple
        case "browser": .green
        case "system": .gray
        case "winKey": .pink
        case "mouse": .orange
        case "scroll": .cyan
        case "window": .mint
        default: .gray
        }
    }

    static func name(of rule: Rule) -> String {
        names[rule.id] ?? rule.id
    }

    private static let names: [String: String] = [
        "edit.copy": String(localized: "Copy"), "edit.cut": String(localized: "Cut"), "edit.paste": String(localized: "Paste"), "edit.undo": String(localized: "Undo"),
        "edit.redo": String(localized: "Redo"), "edit.selectAll": String(localized: "Select all"), "edit.save": String(localized: "Save"), "edit.find": String(localized: "Find"),
        "edit.new": String(localized: "New"), "edit.open": String(localized: "Open"), "edit.print": String(localized: "Print"),
        "nav.lineStart": String(localized: "Line start"), "nav.lineEnd": String(localized: "Line end"),
        "nav.selectLineStart": String(localized: "Select to line start"), "nav.selectLineEnd": String(localized: "Select to line end"),
        "nav.docStart": String(localized: "Document start"), "nav.docEnd": String(localized: "Document end"),
        "nav.selectDocStart": String(localized: "Select to document start"), "nav.selectDocEnd": String(localized: "Select to document end"),
        "nav.wordLeft": String(localized: "Previous word"), "nav.wordRight": String(localized: "Next word"),
        "nav.selectWordLeft": String(localized: "Select previous word"), "nav.selectWordRight": String(localized: "Select next word"),
        "nav.deleteWord": String(localized: "Delete previous word"),
        "finder.trash": String(localized: "Move to Trash"), "finder.rename": String(localized: "Rename"), "finder.open": String(localized: "Open"),
        "dialog.finderFolder": String(localized: "Go to Finder's folder"),
        "finder.cut": String(localized: "Cut (mark to move)"), "finder.move": String(localized: "Move here"), "finder.parent": String(localized: "Enclosing folder"),
        "win.switchApp": String(localized: "Switch apps"), "win.quit": String(localized: "Quit app"), "win.screenshot": String(localized: "Screenshot to clipboard"),
        "win.taskManager": String(localized: "Task Manager (Activity Monitor)"),
        "browser.newTab": String(localized: "New tab"), "browser.closeTab": String(localized: "Close tab"), "browser.reopenTab": String(localized: "Reopen closed tab"),
        "browser.address": String(localized: "Address bar"), "browser.reload": String(localized: "Reload"),
        "sys.forceQuit": String(localized: "Force Quit"),
        "winKey.lock": String(localized: "Lock screen"), "winKey.explorer": String(localized: "File Explorer (Finder)"),
        "winKey.showDesktop": String(localized: "Show desktop"), "winKey.emoji": String(localized: "Emoji & symbols"),
        "winKey.screenshotArea": String(localized: "Screenshot of an area to clipboard"),
        "mouse.back": String(localized: "Back"), "mouse.forward": String(localized: "Forward"),
        "scroll.zoomIn": String(localized: "Zoom in"), "scroll.zoomOut": String(localized: "Zoom out"),
        "window.leftHalf": String(localized: "Snap to the left half"), "window.rightHalf": String(localized: "Snap to the right half"),
        "window.maximize": String(localized: "Fill the screen"),
        "window.minimize": String(localized: "Minimize"),
    ]
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
        return String(localized: "Version \(short) (\(build))")
    }

    var body: some View {
        Card {
            HStack(spacing: 14) {
                AppIcon(size: 40)
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
struct ModeCard: View {
    let engine: EngineController
    var controlKey: ControlKey = .control

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                IconTile(symbol: "command", tint: .accentColor, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Windows Shortcut Mode")
                        .font(.headline)
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if engine.isPaused {
                    Button("Resume") { engine.resume() }
                }
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
            return String(localized: "Unavailable until KeyBridge has the permissions below. macOS does not let an app change shortcuts without them.")
        }
        if !engine.isEnabled {
            return String(localized: "Off. Every key, click and scroll reaches apps unchanged.")
        }
        if let until = engine.pausedUntil {
            return until == .distantFuture
                ? String(localized: "Paused. Every key, click and scroll reaches apps unchanged until you resume.")
                : String(localized: "Paused until \(until.formatted(date: .omitted, time: .shortened)). Every key, click and scroll reaches apps unchanged until then.")
        }
        if !engine.isActive {
            return String(localized: "On, but the event tap could not be started. Quitting and reopening KeyBridge may help.")
        }
        return String(localized: "On. \(copyKey)+C, Home/End, Alt+Tab, the mouse side buttons and scroll zoom work the Windows way.")
    }

    /// The key the user copies with, as they chose on the Shortcuts page.
    private var copyKey: String {
        switch controlKey {
        case .control: String(localized: "Ctrl")
        case .function: String(localized: "fn")
        case .both: String(localized: "Ctrl or fn")
        }
    }
}

/// Whether KeyBridge has what it needs from macOS, and where to grant it.
struct PermissionsCard: View {
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
        AdaptiveRow {
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
            }
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

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
