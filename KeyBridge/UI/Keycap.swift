import AppKit
import SwiftUI

/// One key drawn as a keycap, as the UI mockup does: a light cap with a
/// hairline edge and a shadow line under it.
struct Keycap: View {
    let text: String
    /// Modifier caps are drawn quieter than the key they belong to.
    var isModifier = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isModifier ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            // A cap is as wide as its name: without this, "Shift" and "Home"
            // are squeezed into two lines when the row runs out of room.
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 7)
            .background(.background.secondary, in: shape)
            .overlay(shape.stroke(.separator))
            // The mockup's `box-shadow: 0 1px 0`, which reads as a key edge
            // rather than a drop shadow.
            .background(alignment: .bottom) {
                shape.fill(.separator).offset(y: 1)
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }
}

/// A key combination: its modifiers, then the key itself.
struct KeyComboView: View {
    let combo: KeyCombo
    let style: KeyStyle

    var body: some View {
        HStack(spacing: 3) {
            let modifiers = combo.modifiers.caps(style)
            ForEach(Array(modifiers.enumerated()), id: \.offset) { _, cap in
                Keycap(text: cap, isModifier: true)
                // Windows writes Ctrl+C with a plus; macOS runs ⌘C together.
                if style == .windows {
                    Text("+")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Keycap(text: combo.key.label)
        }
    }
}

/// What a rule does, read left to right: what the user presses, an arrow, and
/// what the Mac receives.
struct MappingView: View {
    let rule: Rule

    var body: some View {
        HStack(spacing: 8) {
            trigger
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.accentColor)
            action
        }
    }

    @ViewBuilder private var trigger: some View {
        switch rule.trigger {
        case .key(let combo):
            KeyComboView(combo: combo, style: .windows)
        case .mouseButton(let number, let modifiers):
            HStack(spacing: 3) {
                ForEach(Array(modifiers.caps(.windows).enumerated()), id: \.offset) { _, cap in
                    Keycap(text: cap, isModifier: true)
                }
                Label("Button \(number)", systemImage: "computermouse")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        case .scroll(let direction, let modifiers):
            HStack(spacing: 3) {
                ForEach(Array(modifiers.caps(.windows).enumerated()), id: \.offset) { _, cap in
                    Keycap(text: cap, isModifier: true)
                    Text("+")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Label(direction.scrollLabel, systemImage: "arrow.up.and.down.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var action: some View {
        switch rule.action {
        case .key(let combo):
            KeyComboView(combo: combo, style: .mac)
        case .openApplication(let bundleID):
            Label(Self.applicationName(bundleID), systemImage: "app")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        case .systemAction(let function):
            SystemActionLabel(action: function)
        case .windowAction(let snap):
            WindowActionLabel(snap: snap)
        case .fileDialog(let action):
            FileDialogActionLabel(action: action)
        }
    }

    /// The application's name as the user knows it, falling back to the
    /// identifier when it is not installed.
    private static func applicationName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}

private extension ScrollDirection {
    var scrollLabel: String {
        switch self {
        case .up: String(localized: "Scroll up")
        case .down: String(localized: "Scroll down")
        case .left: String(localized: "Scroll left")
        case .right: String(localized: "Scroll right")
        }
    }
}
