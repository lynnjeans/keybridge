import SwiftUI

/// The settings window: a sidebar of pages and the selected page beside it.
struct MainWindow: View {
    let engine: EngineController
    let onboarding: OnboardingController
    /// The rules in effect, shown on the Shortcuts page.
    let rules: [Rule]
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
                    ShortcutsList(rules: rules)
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

/// Every rule in effect, as "what you press → what the Mac gets".
///
/// A flat list for now: the preset groups, their switches, search and the
/// per-entry editor arrive with KB-072 and KB-074.
private struct ShortcutsList: View {
    let rules: [Rule]

    var body: some View {
        Card {
            VStack(spacing: 0) {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { Divider() }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        MappingView(rule: rule)
                        Spacer(minLength: 12)
                        Text(Self.name(of: rule))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 9)
                    .opacity(rule.isEnabled ? 1 : 0.5)
                }
            }
        }
    }

    /// What the mapping is for, in the user's terms. Placeholder names until
    /// the preset packs (KB-060) carry their own.
    private static func name(of rule: Rule) -> String {
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
