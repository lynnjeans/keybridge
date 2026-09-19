import AppKit
import SwiftUI

/// The clipboard history's settings and what it holds.
struct ClipboardPage: View {
    let clipboard: ClipboardController
    /// For recording the shortcut through the event tap.
    let rules: RulesController

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
            HotKeyCard(clipboard: clipboard, rules: rules)

            HStack {
                Text("History (\(clipboard.history.items.count))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Keep", selection: Binding(get: { clipboard.limit }, set: { clipboard.limit = $0 })) {
                    ForEach(ClipboardController.limitChoices, id: \.self) { Text("\($0) items").tag($0) }
                }
                .fixedSize()
                .help("Older items are dropped once there are more; pinned items are kept")
                Button("Clear History") { clipboard.history.clear() }
                    .help("Removes everything except pinned items")
                    .disabled(clipboard.history.items.isEmpty)
            }
            Card {
                if clipboard.history.items.isEmpty {
                    Text("Nothing copied yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    // The whole history, in a box of its own that scrolls,
                    // so a long history does not stretch the page.
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(clipboard.history.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider() }
                                ClipboardRow(item: item,
                                             remove: { clipboard.history.remove(item.id) },
                                             setPinned: { clipboard.history.setPinned(item.id, $0) })
                            }
                        }
                        .padding(.trailing, 12)
                    }
                    .frame(height: min(CGFloat(clipboard.history.items.count) * 45, 360))
                    .scrollIndicators(.visible)
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
    var setPinned: ((Bool) -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = Thumbnails.image(for: item) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                IconTile(symbol: symbol, tint: tint, size: 26)
            }
            Text(preview)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let setPinned, isHovered || item.isPinned {
                Button {
                    setPinned(!item.isPinned)
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(item.isPinned ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin" : "Pin: kept whatever the limit")
            }
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
        case .file: item.fileURL?.lastPathComponent ?? String(localized: "File")
        case .image: String(localized: "Image")
        case .text, .richText:
            (item.text ?? String(localized: "Rich text"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
        }
    }
}

/// The shortcut that brings up the history panel.
private struct HotKeyCard: View {
    let clipboard: ClipboardController
    let rules: RulesController
    @State private var recorder = KeyRecorder()
    @State private var isRecording = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open clipboard history")
                            .font(.headline)
                        Text("From any app. Click to record a different shortcut.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    RecorderField(isRecording: isRecording, prompt: "Press a shortcut…",
                                  liveModifiers: recorder.modifiers, style: .mac) {
                        KeyComboView(combo: clipboard.hotKey, style: .mac)
                    } action: {
                        isRecording ? stop() : start()
                    }
                }
                if let problem = clipboard.hotKeyProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else if let conflict {
                    Label("\(conflict) also uses this shortcut; the history panel takes it.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onDisappear { if isRecording { stop() } }
    }

    /// A KeyBridge rule with the same trigger, which the panel would shadow.
    private var conflict: String? {
        rules.effectiveRules.first { $0.isEnabled && $0.trigger == .key(combo: clipboard.hotKey) }
            .map { $0.name ?? RuleNames.name(of: $0) }
    }

    private func start() {
        isRecording = true
        clipboard.suspendHotKey()
        recorder.start(rules: rules, accepting: { if case .key = $0 { true } else { false } }) { trigger in
            if case .key(let combo)? = trigger { clipboard.setHotKey(combo) }
            stop()
        }
    }

    private func stop() {
        recorder.stop()
        isRecording = false
        clipboard.resumeHotKey()
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

/// Small previews of copied images, made once per item. A copied image can
/// be several megabytes; decoding it on every redraw would stall scrolling.
@MainActor
enum Thumbnails {
    private static let cache = NSCache<NSUUID, NSImage>()

    static func image(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        if let cached = cache.object(forKey: item.id as NSUUID) { return cached }
        let data = item.contents[NSPasteboard.PasteboardType.png.rawValue]
            ?? item.contents[NSPasteboard.PasteboardType.tiff.rawValue]
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 96,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: item.id as NSUUID)
        return image
    }
}
