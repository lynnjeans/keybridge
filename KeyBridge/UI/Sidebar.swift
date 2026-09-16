import SwiftUI

/// A page of the main window, in sidebar order.
enum Page: String, CaseIterable, Identifiable, Sendable {
    case overview, shortcuts, mouse, scroll, clipboard, devices
    case customRules, about

    var id: Self { self }

    /// The pages listed above the Advanced heading.
    static let primary: [Page] = [.overview, .shortcuts, .mouse, .scroll, .clipboard, .devices]
    static let advanced: [Page] = [.customRules, .about]

    var title: String {
        switch self {
        case .overview: "Overview"
        case .shortcuts: "Shortcuts"
        case .mouse: "Mouse"
        case .scroll: "Scroll"
        case .clipboard: "Clipboard"
        case .devices: "Devices"
        case .customRules: "Custom Rules"
        case .about: "About"
        }
    }

    /// The line under the page title.
    var subtitle: String {
        switch self {
        case .overview: "See everything at a glance, and switch to the Windows feel in one click."
        case .shortcuts: "Switch whole preset groups on and off, or expand them to fine-tune each entry."
        case .mouse: "Side-button mapping and button actions."
        case .scroll: "Zoom and direction. Mouse only; the trackpad is left alone."
        case .clipboard: "Bring up your copy history at any time, like Win+V on Windows."
        case .devices: "Each keyboard and mouse can be set up on its own."
        case .customRules: "Create any “combination → combination” mapping of your own."
        case .about: "Open source under GPL-3.0, and free."
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .shortcuts: "keyboard.fill"
        case .mouse: "computermouse.fill"
        case .scroll: "arrow.up.and.down"
        case .clipboard: "list.clipboard.fill"
        case .devices: "desktopcomputer"
        case .customRules: "gearshape.fill"
        case .about: "info.circle.fill"
        }
    }

    /// The icon tile's color, as in System Settings.
    var tint: Color {
        switch self {
        case .overview: .green
        case .shortcuts: .indigo
        case .mouse: .orange
        case .scroll: .teal
        case .clipboard: .purple
        case .devices: .pink
        case .customRules: Color(red: 0.39, green: 0.45, blue: 0.55)
        case .about: .gray
        }
    }
}

/// The main window's navigation: the app's name, then every page.
struct Sidebar: View {
    @Binding var selection: Page

    var body: some View {
        List(selection: Binding(get: { selection }, set: { if let page = $0 { selection = page } })) {
            Section {
                ForEach(Page.primary) { row(for: $0) }
            }
            Section("Advanced") {
                ForEach(Page.advanced) { row(for: $0) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { Brand() }
    }

    private func row(for page: Page) -> some View {
        Label {
            Text(page.title)
        } icon: {
            IconTile(symbol: page.symbol, tint: page.tint, size: 20)
        }
        .tag(page)
    }
}

/// The app's name at the top of the sidebar.
private struct Brand: View {
    var body: some View {
        HStack(spacing: 9) {
            IconTile(symbol: "command", tint: .accentColor, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("KeyBridge")
                    .font(.headline)
                Text("Windows → Mac Shortcut Bridge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

/// A white symbol on a rounded colored square, as System Settings draws its
/// sidebar icons.
struct IconTile: View {
    let symbol: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}
