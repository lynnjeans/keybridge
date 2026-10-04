import SwiftUI

/// About › Updates: where SameKeys stands, a manual check, and the two
/// automatic-update choices (KB-101).
struct UpdatesCard: View {
    let updates: UpdateController

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Updates")
                            .font(.headline)
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    button
                }

                if let advice = updates.location.advice {
                    Label(advice, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    // SameKeys can do the move itself (KB-233).
                    Button("Install in Applications Folder") { MoveToApplications.offer(location: updates.location) }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updates.checksAutomatically }, set: { updates.checksAutomatically = $0 }
                    ))
                    Toggle("Download and install updates automatically", isOn: Binding(
                        get: { updates.downloadsAutomatically }, set: { updates.downloadsAutomatically = $0 }
                    ))
                    .disabled(!updates.checksAutomatically)
                }
                .toggleStyle(.checkbox)

                Text("Checking reads the list of versions on SameKeys's website. Nothing about you or this Mac is sent, and this is the only time SameKeys goes online.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var button: some View {
        if let pending = updates.pending, pending.isDownloaded {
            Button("Restart to Update") { updates.installNow() }
        } else if updates.pending != nil {
            Button("Show Update…") { updates.checkForUpdates() }
        } else {
            Button("Check for Updates…") { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
        }
    }

    private var status: String {
        if let pending = updates.pending {
            return pending.isDownloaded
                ? String(localized: "SameKeys \(pending.version) is ready to install. It installs the next time SameKeys quits.")
                : String(localized: "SameKeys \(pending.version) is available.")
        }
        guard let lastCheck = updates.lastCheck else {
            return String(localized: "Not checked yet.")
        }
        return String(localized: "Last checked \(lastCheck.formatted(.relative(presentation: .named))).")
    }
}
