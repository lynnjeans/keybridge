import AppKit
import SwiftUI

/// What GPL-3.0 asks an interactive program to show (its "Appropriate Legal
/// Notices"): the copyright, that there is no warranty, and where the license
/// and the source code are.
struct LegalCard: View {
    static let sourceURL = URL(string: "https://github.com/lynnjeans/keybridge")!

    /// The bundled file open in the viewer.
    @State private var showing: BundledText?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Copyright © 2026 Lei Sun and KeyBridge contributors")
                        .font(.headline)
                    Text("KeyBridge is free software: you can redistribute it and change it under the terms of the GNU General Public License, version 3. It comes with ABSOLUTELY NO WARRANTY.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                WrappingControls {
                    Button("License") { showing = BundledText(file: "LICENSE", title: String(localized: "License")) }
                    Button("Third-Party Notices") {
                        showing = BundledText(file: "THIRD_PARTY_NOTICES.md", title: String(localized: "Third-Party Notices"))
                    }
                    Button("Source Code") { NSWorkspace.shared.open(Self.sourceURL) }
                }
            }
        }
        .sheet(item: $showing) { LegalTextSheet(text: $0) }
    }
}

/// A text file shipped inside the app.
struct BundledText: Identifiable {
    let file: String
    let title: String
    var id: String { file }

    var contents: String {
        Bundle.main.url(forResource: file, withExtension: nil)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? String(localized: "This file is missing from the app. The license and notices are also at \(LegalCard.sourceURL.absoluteString).")
    }
}

/// Shows a bundled file in the app rather than handing it to a text editor,
/// where saving an edit would break the app's code signature.
private struct LegalTextSheet: View {
    let text: BundledText
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(text.contents)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            Divider()
            HStack {
                Text(text.title)
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 520)
    }
}
