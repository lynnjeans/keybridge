import AppKit
import SwiftUI

/// The clipboard history's settings and what it holds.
struct ClipboardPage: View {
    let clipboard: ClipboardController

    var body: some View {
        Card {
            HStack(spacing: 14) {
                IconTile(symbol: "doc.on.clipboard.fill", tint: .purple, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clipboard history")
                        .font(.headline)
                    Text(clipboard.isEnabled
                         ? "Keeps what you copy — text, images and files — on this Mac only."
                         : "Off. Turn it on to keep what you copy, like Win+V on Windows.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("Clipboard history", isOn: Binding(
                    get: { clipboard.isEnabled }, set: { clipboard.isEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }

        if clipboard.isEnabled {
            HStack {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear History") { clipboard.history.clear() }
                    .disabled(clipboard.history.items.isEmpty)
            }
            Card {
                if clipboard.history.items.isEmpty {
                    Text("Nothing copied yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(clipboard.history.items.prefix(20).enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider() }
                            ClipboardRow(item: item) { clipboard.history.remove(item.id) }
                        }
                    }
                }
            }
        }

        ExcludedAppsCard(clipboard: clipboard)

        Label("Passwords from password managers and anything marked as confidential are never recorded. The history stays on this Mac and is never uploaded.", systemImage: "lock.shield")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One copy: what kind it is, a preview, and when.
struct ClipboardRow: View {
    let item: ClipboardItem
    var remove: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint, size: 26)
            Text(preview)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let remove, isHovered {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from history")
            }
            Text(item.date, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 7)
        .onHover { isHovered = $0 }
    }

    private var symbol: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .image: "photo"
        case .file: "doc"
        }
    }

    private var tint: Color {
        switch item.kind {
        case .text, .richText: .teal
        case .image: .pink
        case .file: .gray
        }
    }

    private var preview: String {
        switch item.kind {
        case .file: item.fileURL?.lastPathComponent ?? "File"
        case .image: "Image"
        case .text, .richText:
            (item.text ?? "Rich text")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
        }
    }
}

/// Apps whose copies are never recorded.
private struct ExcludedAppsCard: View {
    let clipboard: ClipboardController

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Never record from")
                            .font(.headline)
                        Text("Password managers are on the list from the start.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add App…") {
                        if let app = AppChooser.choose() { clipboard.exclude(app) }
                    }
                }
                Divider()
                ForEach(clipboard.excludedApps, id: \.self) { id in
                    HStack {
                        AppLabel(bundleID: id)
                        Spacer()
                        Button {
                            clipboard.include(id)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Record this app's copies again")
                    }
                }
                Button("Restore Default List") { clipboard.resetExcludedApps() }
                    .buttonStyle(.link)
                    .disabled(Set(clipboard.excludedApps) == ClipboardPrivacy.defaultExcludedApps)
            }
        }
    }
}
