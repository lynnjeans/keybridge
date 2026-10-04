import CoreGraphics
import Testing

@Suite struct WindowGeometryTests {
    /// A 1512×982 laptop display at the origin, with a second 2560×1440 one
    /// to its left — the layout that exposes negative Accessibility x, since
    /// the origin stays on the primary display wherever the others sit.
    private let laptop = WindowGeometry.Screen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 944)
    )
    private let external = WindowGeometry.Screen(
        frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -2560, y: 25, width: 2560, height: 1415)
    )

    // MARK: - Coordinate flipping

    @Test func flippingTurnsBottomLeftIntoTopLeft() {
        // A window 100 points up from the bottom of a 982-point display, 200
        // tall, sits 682 points down from the top.
        let appKit = CGRect(x: 40, y: 100, width: 300, height: 200)
        let ax = WindowGeometry.flip(appKit, primaryHeight: 982)
        #expect(ax == CGRect(x: 40, y: 682, width: 300, height: 200))
    }

    @Test func flippingTwiceGivesTheOriginalBack() {
        let appKit = CGRect(x: -1200, y: 317, width: 640, height: 480)
        let there = WindowGeometry.flip(appKit, primaryHeight: 982)
        #expect(WindowGeometry.flip(there, primaryHeight: 982) == appKit)
    }

    @Test func aWindowOnTheSecondDisplayFlipsAboveTheOrigin() {
        // The taller external display reaches above the primary one, so in
        // Accessibility coordinates its top is a negative y.
        let appKit = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let ax = WindowGeometry.flip(appKit, primaryHeight: 982)
        #expect(ax.origin.y == -458)
    }

    // MARK: - Choosing a screen

    @Test func aWindowGoesToTheScreenItSitsOn() {
        let window = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(WindowGeometry.screen(for: window, among: [laptop, external]) == laptop)
    }

    @Test func aStraddlingWindowGoesToTheScreenItCoversMost() {
        // 700 points on the external display, 300 on the laptop.
        let window = CGRect(x: -700, y: 200, width: 1000, height: 600)
        #expect(WindowGeometry.screen(for: window, among: [laptop, external]) == external)

        // Nudged across the seam, the majority changes and so does the screen.
        let other = CGRect(x: -300, y: 200, width: 1000, height: 600)
        #expect(WindowGeometry.screen(for: other, among: [laptop, external]) == laptop)
    }

    @Test func aWindowOnNoScreenGoesToTheNearestOne() {
        // Left behind far below both displays, as an unplugged display can do.
        let window = CGRect(x: 200, y: 5000, width: 400, height: 300)
        #expect(WindowGeometry.screen(for: window, among: [laptop, external]) == laptop)
    }

    @Test func thereIsNoScreenWhenThereAreNoScreens() {
        #expect(WindowGeometry.screen(for: .zero, among: []) == nil)
    }

    // MARK: - Fitting

    @Test func aFrameInsideTheScreenIsLeftAlone() {
        let window = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(WindowGeometry.fit(window, in: laptop.visibleFrame) == window)
    }

    @Test func aFrameHangingOverAnEdgeIsPulledBack() {
        let window = CGRect(x: 1400, y: 900, width: 800, height: 600)
        let fitted = WindowGeometry.fit(window, in: laptop.visibleFrame)
        #expect(fitted == CGRect(x: 712, y: 382, width: 800, height: 600))
    }

    @Test func aFrameAboveTheMenuBarIsPushedDown() {
        let window = CGRect(x: 100, y: 0, width: 400, height: 300)
        let fitted = WindowGeometry.fit(window, in: laptop.visibleFrame)
        #expect(fitted.origin.y == 38)
    }

    @Test func aFrameLargerThanTheScreenIsShrunkToIt() {
        let window = CGRect(x: -200, y: -200, width: 4000, height: 3000)
        #expect(WindowGeometry.fit(window, in: laptop.visibleFrame) == laptop.visibleFrame)
    }

    @Test func fittingWorksOnADisplayLeftOfTheOrigin() {
        let window = CGRect(x: -3000, y: 1300, width: 900, height: 700)
        let fitted = WindowGeometry.fit(window, in: external.visibleFrame)
        #expect(fitted == CGRect(x: -2560, y: 740, width: 900, height: 700))
    }
}
