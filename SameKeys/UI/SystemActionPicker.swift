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
        case .inputSource: String(localized: "Switch input source")
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
        case .inputSource: "globe"
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

/// What the System function result can do: one of macOS's functions, or
/// SameKeys's clipboard history, which is Win+V's system function on Windows.
/// A choice in the editors only; the rule keeps its own action for each.
enum SystemFunction: Hashable {
    case system(SystemAction)
    case clipboardHistory

    static let all = SystemAction.allCases.map(SystemFunction.system) + [.clipboardHistory]

    /// Nil for an action the System function result does not cover.
    init?(_ action: Action) {
        switch action {
        case .systemAction(let function): self = .system(function)
        case .clipboardHistory: self = .clipboardHistory
        default: return nil
        }
    }

    var action: Action {
        switch self {
        case .system(let function): .systemAction(function)
        case .clipboardHistory: .clipboardHistory
        }
    }

    var name: String {
        switch self {
        case .system(let function): function.name
        case .clipboardHistory: String(localized: "Clipboard history")
        }
    }

    var symbol: String {
        switch self {
        case .system(let function): function.symbol
        case .clipboardHistory: "list.clipboard"
        }
    }
}

/// Chooses a system function, and says what triggering it does on this Mac:
/// which shortcut SameKeys will press, or that System Settings has none.
struct SystemActionPicker: View {
    @Binding var selection: SystemFunction
    /// Read when the editor opens; System Settings may change meanwhile, but
    /// the shortcut is read again whenever the rule fires.
    @State private var hotKeys = SymbolicHotKeys.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("System function", selection: $selection) {
                ForEach(SystemFunction.all, id: \.self) { function in
                    Label(function.name, systemImage: function.symbol).tag(function)
                }
            }
            .labelsHidden()
            .fixedSize()
            status
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // Wrapped rather than widening the editor to its length.
                .frame(maxWidth: 420, alignment: .leading)
        }
        .onAppear { hotKeys = SymbolicHotKeys.current() }
    }

    @ViewBuilder private var status: some View {
        switch selection {
        case .clipboardHistory:
            Text("Shows or hides the clipboard history, as its own shortcut does. Does nothing while the history is off.")
        case .system(.inputSource):
            Text("Switches between ABC and the input method you used last, such as Pinyin, like Caps Lock does, without the input source switcher on screen.")
        case .system(let function):
            shortcutStatus(function)
        }
    }

    @ViewBuilder private func shortcutStatus(_ function: SystemAction) -> some View {
        switch hotKeys.shortcut(for: function) {
        case .combo(let combo):
            HStack(spacing: 6) {
                Text("Presses your shortcut for it:")
                KeyComboView(combo: combo, style: .mac)
            }
        case let missing:
            VStack(alignment: .leading, spacing: 6) {
                if function.fallbackApplication != nil {
                    Text(missing == .off
                         ? "Its shortcut is switched off in System Settings, so SameKeys opens it directly."
                         : "It has no shortcut in System Settings, so SameKeys opens it directly.")
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
