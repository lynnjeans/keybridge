import AppKit
import SwiftUI

extension SystemAction {
    /// The function's name as System Settings words it.
    var name: String {
        switch self {
        case .missionControl: String(localized: "Mission Control")
        case .applicationWindows: String(localized: "Application windows")
        case .showDesktop: String(localized: "Show Desktop")
        case .apps:
            if #available(macOS 26, *) { String(localized: "Apps") } else { String(localized: "Launchpad") }
        case .spaceLeft: String(localized: "Move left a space")
        case .spaceRight: String(localized: "Move right a space")
        case .spotlight: String(localized: "Spotlight")
        }
    }

    var symbol: String {
        switch self {
        case .missionControl: "rectangle.3.group"
        case .applicationWindows: "macwindow.on.rectangle"
        case .showDesktop: "menubar.dock.rectangle"
        case .apps: "square.grid.3x3"
        case .spaceLeft: "arrow.left.square"
        case .spaceRight: "arrow.right.square"
        case .spotlight: "magnifyingglass"
        }
    }
}

/// A system function as a rule's result, in lists.
struct SystemActionLabel: View {
    let action: SystemAction

    var body: some View {
        Label(action.name, systemImage: action.symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// Chooses a system function, and says what triggering it does on this Mac:
/// which shortcut KeyBridge will press, or that System Settings has none.
struct SystemActionPicker: View {
    @Binding var selection: SystemAction
    /// Read when the editor opens; System Settings may change meanwhile, but
    /// the shortcut is read again whenever the rule fires.
    @State private var hotKeys = SymbolicHotKeys.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("System function", selection: $selection) {
                ForEach(SystemAction.allCases, id: \.self) { action in
                    Label(action.name, systemImage: action.symbol).tag(action)
                }
            }
            .labelsHidden()
            .fixedSize()
            status
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { hotKeys = SymbolicHotKeys.current() }
    }

    @ViewBuilder private var status: some View {
        switch hotKeys.shortcut(for: selection) {
        case .combo(let combo):
            HStack(spacing: 6) {
                Text("Presses your shortcut for it:")
                KeyComboView(combo: combo, style: .mac)
            }
        case let missing:
            VStack(alignment: .leading, spacing: 6) {
                if selection.fallbackApplication != nil {
                    Text(missing == .off
                         ? "Its shortcut is switched off in System Settings, so KeyBridge opens it directly."
                         : "It has no shortcut in System Settings, so KeyBridge opens it directly.")
                } else {
                    Text(missing == .off
                         ? "Its shortcut is switched off in System Settings, so this does nothing until you switch it on."
                         : "It has no shortcut in System Settings, so this does nothing until you give it one.")
                }
                Button("Open Keyboard Shortcuts…") { Self.openKeyboardSettings() }
                    .controlSize(.small)
            }
        }
    }

    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
