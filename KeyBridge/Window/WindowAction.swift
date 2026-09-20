import CoreGraphics

/// What a rule does to the window in front (KB-201).
///
/// Raw values are saved in the configuration and must never change.
enum WindowAction: String, Codable, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    /// Fills the screen's usable area. Deliberately not the green button's
    /// full-screen space: the menu bar and the Dock stay, the window keeps its
    /// title bar, and other windows can still sit on top — which is what
    /// Windows' Win+↑ does and what someone coming from it expects.
    case maximize
    /// Sends the window to the Dock, as Win+↓ does on Windows. The only one
    /// here that does not give the window a frame.
    case minimize

    /// Whether this action moves and resizes the window rather than doing
    /// something else with it.
    var movesWindow: Bool { self != .minimize }

    /// The frame this action gives a window on `screen`, or nil for an action
    /// that does not move one.
    ///
    /// Computed from the screen's usable area, so the result clears the menu
    /// bar and the Dock wherever they are. Halves split the width and take the
    /// full usable height; an odd width gives the extra point to the left half
    /// rather than leaving a one-point gap down the middle.
    func frame(on screen: WindowGeometry.Screen) -> CGRect? {
        let visible = screen.visibleFrame
        switch self {
        case .minimize:
            return nil
        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY,
                          width: (visible.width / 2).rounded(.up), height: visible.height)
        case .rightHalf:
            let width = (visible.width / 2).rounded(.down)
            return CGRect(x: visible.maxX - width, y: visible.minY,
                          width: width, height: visible.height)
        case .maximize:
            return visible
        }
    }

    /// The frame for a window currently at `frame`, on whichever screen it
    /// mostly sits on. Nil when there are no screens, and for an action that
    /// does not move the window.
    ///
    /// The window stays on its own display: a snap is for arranging what is in
    /// front of you, not for throwing windows onto another monitor.
    func frame(for frame: CGRect, among screens: [WindowGeometry.Screen]) -> CGRect? {
        guard let screen = WindowGeometry.screen(for: frame, among: screens) else { return nil }
        return self.frame(on: screen)
    }
}
