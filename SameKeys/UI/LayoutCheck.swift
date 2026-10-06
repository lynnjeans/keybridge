#if DEBUG
import AppKit
import Foundation

/// Opens windows and pages at launch so layouts can be screenshotted in each
/// language without clicking (KB-092). Debug builds only:
///
///     open SameKeys.app --env KB_DEBUG_SHOW=main --env KB_DEBUG_PAGE=shortcuts \
///         --args -AppleLanguages '(ja)'
///
/// - `KB_DEBUG_SHOW`: `main`, `onboarding` or `clipboard` (the history
///   panel).
/// - `KB_DEBUG_PAGE`: a `Page` raw value, shown in the main window.
/// - `KB_DEBUG_EXPAND_ALL`: every Shortcuts group starts expanded.
/// - `KB_DEBUG_RULE_EDITOR`: the Custom Rules page opens the editor on a
///   new rule, and the Mouse page on the back button (KB-245).
/// - `KB_DEBUG_STEP`: the guide shows `accessibility`, `inputMonitoring` or
///   `ready`, whatever the permissions say.
/// - `KB_DEBUG_KEYBOARDS`: `pc` (one PC keyboard, as on a Mac mini), `mac`
///   (the built-in one only) or `both`, in place of those connected, for the
///   Shortcuts page's per-keyboard rows (KB-076).
/// - `KB_DEBUG_LOGINITEM`: `on` or `off`; Open at Login starts that way and
///   can be switched, without this Mac's login items being touched. Without
///   it a copy outside Applications shows the switch unavailable.
/// - `KB_DEBUG_APPEARANCE`: `light` or `dark`, whatever the Mac's own
///   appearance, for the website's screenshots (KB-105).
///
/// `-NSDoubleLocalizedStrings YES` among the arguments doubles every string,
/// a stand-in for a language longer than any shipped one.
@MainActor
enum LayoutCheck {
    private static let environment = ProcessInfo.processInfo.environment

    static var page: Page? { environment["KB_DEBUG_PAGE"].flatMap(Page.init(rawValue:)) }
    static var expandsAllGroups: Bool { environment["KB_DEBUG_EXPAND_ALL"] != nil }
    static var opensRuleEditor: Bool { environment["KB_DEBUG_RULE_EDITOR"] != nil }

    /// The keyboards the Shortcuts page shows, in place of those connected.
    static var keyboards: [Keyboard]? {
        let builtIn = Keyboard(vendorID: 0, productID: 0, name: "Apple Internal Keyboard / Trackpad", isBuiltIn: true)
        let pc = Keyboard(vendorID: 0x046D, productID: 0xC31C, name: "Logitech USB Keyboard", isBuiltIn: false)
        switch environment["KB_DEBUG_KEYBOARDS"] {
        case "pc": return [pc]
        case "mac": return [builtIn]
        case "both": return [builtIn, pc]
        default: return nil
        }
    }

    /// The guide's step, whatever the permissions say.
    static var onboardingStep: OnboardingController.Step? {
        switch environment["KB_DEBUG_STEP"] {
        case "accessibility": .accessibility
        case "inputMonitoring": .inputMonitoring
        case "ready": .ready
        default: nil
        }
    }

    /// Open at Login as a stand-in that only remembers the switch. The real
    /// one is left to the copy in Applications (`LoginItem.isAvailable`).
    static var loginItem: LoginItem? {
        switch environment["KB_DEBUG_LOGINITEM"] {
        case "on": LoginItem(isAvailable: true, system: .inMemory(isEnabled: true))
        case "off": LoginItem(isAvailable: true, system: .inMemory(isEnabled: false))
        default: nil
        }
    }

    static func showRequestedWindow(clipboardPanel: ClipboardPanelController) {
        switch environment["KB_DEBUG_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        guard let window = environment["KB_DEBUG_SHOW"] else { return }
        // The notifications are received by the menu bar icon, which SwiftUI
        // installs only after launch finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            switch window {
            case "main": NotificationCenter.default.post(name: .openMainWindow, object: nil)
            case "onboarding": NotificationCenter.default.post(name: .openOnboarding, object: nil)
            case "clipboard": clipboardPanel.show()
            default: break
            }
        }
    }
}
#endif
