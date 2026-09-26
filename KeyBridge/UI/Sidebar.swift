import SwiftUI

/// A page of the main window, in sidebar order.
enum Page: String, CaseIterable, Identifiable, Sendable {
    case overview, shortcuts, mouse, scroll, clipboard, finder, devices
    case customRules, about

    var id: Self { self }

    /// The pages listed above the Advanced heading.
    // Devices waits for per-device rules in v1.1 (#98).
    static let primary: [Page] = [.overview, .shortcuts, .mouse, .scroll, .clipboard, .finder]
    static let advanced: [Page] = [.customRules, .about]

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .shortcuts: String(localized: "Shortcuts")
        case .mouse: String(localized: "Mouse")
        case .scroll: String(localized: "Scroll")
        case .clipboard: String(localized: "Clipboard")
        case .finder: String(localized: "Finder")
        case .devices: String(localized: "Devices")
        case .customRules: String(localized: "Custom Rules")
        case .about: String(localized: "About")
        }
    }

    /// The line under the page title.
    var subtitle: String {
        switch self {
        case .overview: String(localized: "See everything at a glance, and switch to the Windows feel in one click.")
        case .shortcuts: String(localized: "Switch whole preset groups on and off, or expand them to fine-tune each entry.")
        case .mouse: String(localized: "Side-button mapping and button actions.")
        case .scroll: String(localized: "Zoom and direction. Mouse only; the trackpad is left alone.")
        case .clipboard: String(localized: "Bring up your copy history at any time, like Win+V on Windows.")
        case .finder: String(localized: "Right-click menu, a path box, and open and save dialogs that jump to where Finder is.")
        case .devices: String(localized: "Each keyboard and mouse can be set up on its own.")
        case .customRules: String(localized: "Create any “combination → combination” mapping of your own.")
        case .about: String(localized: "Open source under GPL-3.0, and free.")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .shortcuts: "keyboard.fill"
        case .mouse: "computermouse.fill"
        case .scroll: "arrow.up.and.down"
        case .clipboard: "list.clipboard.fill"
        case .finder: "folder.fill"
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
        case .finder: .blue
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LanguagePicker()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
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
            AppIcon(size: 30)
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
/// KeyBridge's own icon (KB-106), as macOS draws it: Liquid Glass on macOS 26.
/// The system's rendering leaves a margin round the tile, so it is drawn a
/// little larger than `size` to line up with the `IconTile`s beside it.
struct AppIcon: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .frame(width: size * 1.22, height: size * 1.22)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

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
