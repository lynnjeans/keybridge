#if DEBUG
import AppKit
import Foundation

/// Opens windows and pages at launch so layouts can be screenshotted in each
/// language without clicking (KB-092). Debug builds only:
///
///     open KeyBridge.app --env KB_DEBUG_SHOW=main --env KB_DEBUG_PAGE=shortcuts \
///         --args -AppleLanguages '(ja)'
///
/// - `KB_DEBUG_SHOW`: `main`, `onboarding`, `clipboard` (the history panel)
///   or `pathbox` (the path box, as ⌘L over Finder would open it).
/// - `KB_DEBUG_PAGE`: a `Page` raw value, shown in the main window.
/// - `KB_DEBUG_EXPAND_ALL`: every Shortcuts group starts expanded.
///
/// `-NSDoubleLocalizedStrings YES` among the arguments doubles every string,
/// a stand-in for a language longer than any shipped one.
@MainActor
enum LayoutCheck {
    private static let environment = ProcessInfo.processInfo.environment

    static var page: Page? { environment["KB_DEBUG_PAGE"].flatMap(Page.init(rawValue:)) }
    static var expandsAllGroups: Bool { environment["KB_DEBUG_EXPAND_ALL"] != nil }

    static func showRequestedWindow(clipboardPanel: ClipboardPanelController, pathBox: PathBoxController) {
        guard let window = environment["KB_DEBUG_SHOW"] else { return }
        // The notifications are received by the menu bar icon, which SwiftUI
        // installs only after launch finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            switch window {
            case "main": NotificationCenter.default.post(name: .openMainWindow, object: nil)
            case "onboarding": NotificationCenter.default.post(name: .openOnboarding, object: nil)
            case "clipboard": clipboardPanel.show()
            case "pathbox": pathBox.showPanel?()
            default: break
            }
        }
    }
}
#endif
