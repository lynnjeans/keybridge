import AppKit
import SwiftUI

/// The first page: the master switch, the preset in use, a few counts, the
/// permissions and whatever deserves a word right now.
struct OverviewPage: View {
    let engine: EngineController
    let onboarding: OnboardingController
    let rules: RulesController
    let open: (Page) -> Void

    var body: some View {
        ModeCard(engine: engine, controlKey: rules.controlKey)

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
        return "\(groupsOn) of \(rules.preset.groups.count) groups on. Every entry can be changed on the Shortcuts, Mouse and Scroll pages."
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
