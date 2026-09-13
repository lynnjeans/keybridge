import SwiftUI

/// The settings window. Shows the Overview for now; the sidebar and the other
/// pages arrive with KB-070.
struct MainWindow: View {
    let engine: EngineController
    let onboarding: OnboardingController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Overview")
                    .font(.largeTitle.bold())
                ModeCard(engine: engine)
                PermissionsCard(permissions: engine.permissions, onboarding: onboarding)
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 720, minHeight: 480)
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
                        .foregroundStyle(.tertiary)
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
