import CoreGraphics

/// Where a snap puts a window (KB-201).
///
/// Raw values are saved in the configuration and must never change.
enum WindowSnap: String, Codable, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    /// Fills the screen's usable area. Deliberately not the green button's
    /// full-screen space: the menu bar and the Dock stay, the window keeps its
    /// title bar, and other windows can still sit on top — which is what
    /// Windows' Win+↑ does and what someone coming from it expects.
    case maximize

    /// The frame this snap gives a window on `screen`.
    ///
    /// Computed from the screen's usable area, so the result clears the menu
    /// bar and the Dock wherever they are. Halves split the width and take the
    /// full usable height; an odd width gives the extra point to the left half
    /// rather than leaving a one-point gap down the middle.
    func frame(on screen: WindowGeometry.Screen) -> CGRect {
        let visible = screen.visibleFrame
        switch self {
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
    /// mostly sits on. Nil when there are no screens.
    ///
    /// The window stays on its own display: a snap is for arranging what is in
    /// front of you, not for throwing windows onto another monitor.
    func frame(for frame: CGRect, among screens: [WindowGeometry.Screen]) -> CGRect? {
        guard let screen = WindowGeometry.screen(for: frame, among: screens) else { return nil }
        return self.frame(on: screen)
    }
}
