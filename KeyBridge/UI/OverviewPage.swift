import AppKit
import SwiftUI

/// The first page: the master switch, the preset in use, a few counts, the
/// permissions and whatever deserves a word right now.
struct OverviewPage: View {
    let engine: EngineController
    let onboarding: OnboardingController
    let rules: RulesController
    let secureInput: SecureInputMonitor
    let open: (Page) -> Void

    var body: some View {
        ModeCard(engine: engine, controlKey: rules.controlKey)

        if engine.isActive, let holder = secureInput.holder {
            SecureInputNotice(holder: holder, isLingering: secureInput.isLingering)
        }

        Card {
            HStack(spacing: 14) {
                IconTile(symbol: "list.bullet.rectangle", tint: .indigo, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preset: \(RuleNames.presetName(rules.preset.id))")
                        .font(.headline)
                    Text(presetDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Customize…") { open(.shortcuts) }
                RestoreDefaultsButton(rules: rules)
            }
        }

        HStack(spacing: 12) {
            StatTile(value: rules.activeRuleCount, label: "Active rules")
            StatTile(value: rules.customizedCount, label: "Customized")
            StatTile(value: rules.exceptionApps.count, label: "App exceptions")
        }

        if engine.permissions.allGranted {
            PermissionsSummary()
        } else {
            PermissionsCard(permissions: engine.permissions, onboarding: onboarding)
        }

        ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
            Label {
                Text(notice).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private var presetDetail: LocalizedStringKey {
        let groupsOn = rules.preset.groups.filter { rules.isEnabled(group: $0.id) }.count
        let changed = rules.customizedCount
        return changed == 0
            ? "\(groupsOn) of \(rules.preset.groups.count) groups on."
            : "\(groupsOn) of \(rules.preset.groups.count) groups on, \(changed) entries customized."
    }

    /// Things worth knowing about the current setup, each only while it
    /// applies.
    private var notices: [LocalizedStringKey] {
        var notices: [LocalizedStringKey] = []
        if rules.exceptionApps.contains(where: BuiltInRules.terminals.contains) {
            notices.append(rules.controlKey == .function
                ? "Home, End and Ctrl+arrow keys are left alone in terminals; fn shortcuts work there too."
                : "Ctrl shortcuts are left alone in terminals, where Ctrl+C stops the running program.")
        }
        if rules.isEnabled(group: "winKey") {
            notices.append("Windows key shortcuts are on, so ⌘L, ⌘E, ⌘D, ⌘. and ⌘⇧S are taken on a Mac keyboard too.")
        }
        return notices
    }
}

/// One count, large, with what it counts under it.
private struct StatTile: View {
    let value: Int
    let label: LocalizedStringKey

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(value, format: .number)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The permissions in one line once everything is granted; the full card,
/// with a row per permission, takes over as soon as one is missing.
private struct PermissionsSummary: View {
    var body: some View {
        Card {
            HStack(spacing: 14) {
                IconTile(symbol: "checkmark", tint: .green, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Permissions")
                        .font(.headline)
                    Text("Accessibility and Input Monitoring are both granted.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("Ready")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.14), in: Capsule())
            }
        }
    }
}

/// Says why keyboard rules are doing nothing while Secure Input is on.
private struct SecureInputNotice: View {
    let holder: SecureInputMonitor.Holder
    let isLingering: Bool

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                IconTile(symbol: "lock.fill", tint: .orange, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard shortcuts paused by macOS")
                        .font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var detail: String {
        // Whole sentences, so each language can order them its own way.
        var parts = [holder.appName.map {
            String(localized: "\($0) has turned on Secure Input, which hides key presses from apps like KeyBridge — a macOS safeguard for passwords, not a fault. Mouse buttons and scrolling still work.")
        } ?? String(localized: "An app has turned on Secure Input, which hides key presses from apps like KeyBridge — a macOS safeguard for passwords, not a fault. Mouse buttons and scrolling still work.")]
        if isLingering {
            parts.append(String(localized: "It has been on for a while, so it is probably not a password field."))
            parts.append(holder.switchOffHint ?? holder.appName.map { String(localized: "Quitting \($0) ends it.") }
                ?? String(localized: "Quitting that app ends it."))
        } else {
            parts.append(String(localized: "It ends when you leave the password field."))
        }
        return parts.joined(separator: " ")
    }

}

/// Puts the preset back as it ships, after asking.
struct RestoreDefaultsButton: View {
    let rules: RulesController
    @State private var confirming = false

    var body: some View {
        Button("Restore Defaults…") { confirming = true }
            .disabled(rules.isDefault)
            .help(rules.isDefault ? "The preset is as it ships" : "Undo every change to the preset")
            .alert("Restore the preset's defaults?", isPresented: $confirming) {
                Button("Restore Defaults", role: .destructive) { rules.restoreDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All groups and entries go back to the preset. Your custom rules are kept.")
            }
    }
}
