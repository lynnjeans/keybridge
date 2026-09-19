import SwiftUI

/// The side buttons: which button does what, each entry editable.
struct MousePage: View {
    let rules: RulesController
    @State private var editing: Rule?

    var body: some View {
        Card {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    IconTile(symbol: RuleNames.symbol(ofGroup: "mouse"), tint: RuleNames.tint(ofGroup: "mouse"), size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Side buttons")
                            .font(.headline)
                        Text("Back and forward in browsers and Finder, like on Windows.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    GroupSwitch(rules: rules, group: "mouse", label: "Side buttons")
                }
                Divider().padding(.top, 12)
                EntryList(rules: rules, group: "mouse", edit: { editing = $0 })
            }
        }

        Text("Click an entry, then press the mouse button it should use; its number is shown. The left and right buttons cannot be remapped. A mouse's own software, or tools such as Karabiner-Elements, may remap buttons before KeyBridge sees them.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .sheet(item: $editing) { RuleEditor(rules: rules, rule: $0) }
    }
}

/// Page zoom with modifier + wheel, and which modifier that is.
struct ScrollPage: View {
    let rules: RulesController
    @State private var editing: Rule?
    /// Shows the modifier checkboxes even when the choice is a single key.
    @State private var showsCustom = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    IconTile(symbol: "plus.magnifyingglass", tint: RuleNames.tint(ofGroup: "scroll"), size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zoom with modifier + scroll")
                            .font(.headline)
                        Text("Zooms pages and documents, like Ctrl+wheel on Windows.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    GroupSwitch(rules: rules, group: "scroll", label: "Zoom with modifier + scroll")
                }
                Divider().padding(.vertical, 12)
                modifierPicker
                if rules.zoomModifiers == [.control] {
                    Label {
                        Text("macOS can zoom the whole screen with Ctrl+scroll (Accessibility › Zoom › “Use scroll gesture with modifier keys”). If that is on, it wins and pages do not zoom: choose fn, or turn it off.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                    .font(.callout)
                    .padding(.top, 10)
                }
                Divider().padding(.top, 12)
                EntryList(rules: rules, group: "scroll", edit: { editing = $0 })
            }
        }

        Card {
            HStack(spacing: 12) {
                IconTile(symbol: "arrow.up.arrow.down", tint: .teal, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Windows scroll direction")
                        .font(.headline)
                    Text(directionNote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("Windows scroll direction", isOn: Binding(
                    get: { rules.wheelDirection == .windows },
                    set: { rules.setWheelDirection($0 ? .windows : .system) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }

        Text("Only mouse wheels. Trackpad and Magic Mouse scrolling are left to the system.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .sheet(item: $editing) { RuleEditor(rules: rules, rule: $0) }
    }

    /// macOS applies natural scrolling to the trackpad and every mouse at
    /// once. With it off, wheels already scroll the Windows way.
    private var directionNote: LocalizedStringKey {
        let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        return natural
            ? "Rolling the wheel towards you moves down the page. The trackpad keeps natural scrolling."
            : "Natural scrolling is off in System Settings, so wheels already scroll this way."
    }

    private static let singles: [(Modifiers, LocalizedStringKey)] = [
        ([.function], "fn"), ([.control], "Ctrl"), ([.option], "⌥ Option"), ([.command], "⌘ Command"),
    ]

    private var choice: Binding<Modifiers?> {
        Binding(
            get: {
                let current = rules.zoomModifiers
                return !showsCustom && Self.singles.contains { $0.0 == current } ? current : nil
            },
            set: { modifiers in
                if let modifiers {
                    showsCustom = false
                    rules.setZoomModifiers(modifiers)
                } else {
                    showsCustom = true
                }
            }
        )
    }

    private var modifierPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The label apart from the menu, so a long translation wraps
            // instead of making the page wider than the window.
            AdaptiveRow(minFlexibleWidth: 140) {
                Text("Hold while scrolling")
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Hold while scrolling", selection: choice) {
                    ForEach(Self.singles, id: \.0.rawValue) { modifiers, name in
                        Text(name).tag(Optional(modifiers))
                    }
                    Divider()
                    Text("Custom…").tag(Modifiers?.none)
                }
                .labelsHidden()
                .fixedSize()
            }

            if choice.wrappedValue == nil {
                HStack(spacing: 14) {
                    ForEach(Self.customizable, id: \.0.rawValue) { modifier, name in
                        Toggle(name, isOn: Binding(
                            get: { rules.zoomModifiers.contains(modifier) },
                            set: { isOn in
                                var modifiers = rules.zoomModifiers
                                if isOn { modifiers.insert(modifier) } else { modifiers.remove(modifier) }
                                // Plain scrolling must never zoom.
                                if !modifiers.isEmpty { rules.setZoomModifiers(modifiers) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                if rules.zoomModifiers.contains(.shift) {
                    Text("Shift+scroll scrolls sideways in most apps; with Shift it no longer does.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let customizable: [(Modifiers, LocalizedStringKey)] = [
        ([.control], "Ctrl"), ([.option], "⌥"), ([.shift], "⇧"), ([.command], "⌘"), ([.function], "fn"),
    ]
}

/// A group's on/off switch, saving at once.
private struct GroupSwitch: View {
    let rules: RulesController
    let group: String
    let label: LocalizedStringKey

    var body: some View {
        Toggle(label, isOn: Binding(get: { rules.isEnabled(group: group) },
                                    set: { rules.setGroup(group, enabled: $0) }))
            .toggleStyle(.switch)
            .labelsHidden()
    }
}

/// A group's entries, each opening the editor, greyed out while the group is
/// off.
private struct EntryList: View {
    let rules: RulesController
    let group: String
    let edit: (Rule) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rules.rules(inGroup: group).enumerated()), id: \.element.id) { index, rule in
                if index > 0 { Divider() }
                EntryRow(rule: rule, trigger: rule.trigger, isCustomized: rules.isCustomized(rule.id)) { edit(rule) }
            }
        }
        .opacity(rules.isEnabled(group: group) ? 1 : 0.45)
    }
}
