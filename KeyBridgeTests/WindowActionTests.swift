import CoreGraphics
import Testing

@Suite struct WindowActionTests {
    /// The primary laptop display, and a taller external one to its left.
    /// Accessibility coordinates: the origin is the primary display's
    /// top-left, so the external display's x is negative and its top is above
    /// zero. Both leave room for the menu bar; the laptop also has the Dock.
    private let laptop = WindowGeometry.Screen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 862)
    )
    private let external = WindowGeometry.Screen(
        frame: CGRect(x: -2560, y: -458, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -2560, y: -433, width: 2560, height: 1415)
    )

    /// The actions that give a window a frame — everything but minimize.
    private var moving: [WindowAction] { WindowAction.allCases.filter(\.movesWindow) }

    // MARK: - On one screen

    @Test func theLeftHalfTakesTheLeftOfTheUsableArea() throws {
        let frame = try #require(WindowAction.leftHalf.frame(on: laptop))
        #expect(frame == CGRect(x: 0, y: 38, width: 756, height: 862))
    }

    @Test func theRightHalfTakesTheRightOfTheUsableArea() throws {
        let frame = try #require(WindowAction.rightHalf.frame(on: laptop))
        #expect(frame == CGRect(x: 756, y: 38, width: 756, height: 862))
    }

    @Test func theTwoHalvesMeetWithNoGapAndNoOverlap() throws {
        let left = try #require(WindowAction.leftHalf.frame(on: laptop))
        let right = try #require(WindowAction.rightHalf.frame(on: laptop))
        #expect(left.maxX == right.minX)
        #expect(left.width + right.width == laptop.visibleFrame.width)
    }

    @Test func anOddWidthGivesTheExtraPointToTheLeftHalf() throws {
        let odd = WindowGeometry.Screen(
            frame: CGRect(x: 0, y: 0, width: 1367, height: 800),
            visibleFrame: CGRect(x: 0, y: 25, width: 1367, height: 775)
        )
        let left = try #require(WindowAction.leftHalf.frame(on: odd))
        let right = try #require(WindowAction.rightHalf.frame(on: odd))
        #expect(left.width == 684)
        #expect(right.width == 683)
        // Still no gap and nothing hanging off the edge.
        #expect(left.maxX == right.minX)
        #expect(right.maxX == odd.visibleFrame.maxX)
    }

    @Test func maximizeFillsTheUsableAreaAndNotTheWholeScreen() throws {
        let frame = try #require(WindowAction.maximize.frame(on: laptop))
        #expect(frame == laptop.visibleFrame)
        // The menu bar and the Dock keep their space: this is not full screen.
        #expect(frame != laptop.frame)
        #expect(frame.minY > laptop.frame.minY)
    }

    @Test func everyMovingActionStaysInsideTheUsableArea() {
        for action in moving {
            for screen in [laptop, external] {
                let frame = action.frame(on: screen)
                #expect(frame.map(screen.visibleFrame.contains) == true, "\(action) on \(screen.visibleFrame)")
            }
        }
    }

    // MARK: - Minimize

    @Test func minimizeDoesNotGiveTheWindowAFrame() {
        #expect(WindowAction.minimize.movesWindow == false)
        #expect(WindowAction.minimize.frame(on: laptop) == nil)
        #expect(WindowAction.minimize.frame(for: .zero, among: [laptop]) == nil)
    }

    @Test func everyOtherActionMovesTheWindow() {
        #expect(moving == [.leftHalf, .rightHalf, .maximize])
        for action in moving {
            #expect(action.frame(on: laptop) != nil, "\(action)")
        }
    }

    // MARK: - Across displays

    @Test func aWindowSnapsOnTheDisplayItSitsOn() {
        let onLaptop = CGRect(x: 200, y: 200, width: 600, height: 400)
        #expect(WindowAction.leftHalf.frame(for: onLaptop, among: [laptop, external])
                == WindowAction.leftHalf.frame(on: laptop))

        let onExternal = CGRect(x: -2000, y: 0, width: 600, height: 400)
        #expect(WindowAction.leftHalf.frame(for: onExternal, among: [laptop, external])
                == WindowAction.leftHalf.frame(on: external))
    }

    @Test func snappingOnTheSecondDisplayUsesItsOwnCoordinates() throws {
        let onExternal = CGRect(x: -2000, y: 0, width: 600, height: 400)
        let frame = try #require(WindowAction.rightHalf.frame(for: onExternal, among: [laptop, external]))
        // The right half of the display left of the origin is still negative.
        #expect(frame == CGRect(x: -1280, y: -433, width: 1280, height: 1415))
        #expect(frame.maxX == 0)
    }

    @Test func aStraddlingWindowSnapsOnTheDisplayItMostlyCovers() {
        // 700 points on the external display, 300 on the laptop.
        let straddling = CGRect(x: -700, y: 100, width: 1000, height: 600)
        #expect(WindowAction.maximize.frame(for: straddling, among: [laptop, external])
                == external.visibleFrame)
    }

    @Test func snappingDoesNotMoveAWindowToAnotherDisplay() {
        // Whatever the action, the result stays on the screen the window was on.
        let onLaptop = CGRect(x: 900, y: 500, width: 400, height: 300)
        for action in moving {
            let frame = action.frame(for: onLaptop, among: [laptop, external])
            #expect(frame.map(laptop.visibleFrame.contains) == true, "\(action)")
        }
    }

    @Test func thereIsNothingToComputeWithoutScreens() {
        #expect(WindowAction.leftHalf.frame(for: .zero, among: []) == nil)
    }

    // MARK: - Configuration

    @Test func rawValuesAreStableForTheConfigurationFile() {
        #expect(WindowAction.leftHalf.rawValue == "leftHalf")
        #expect(WindowAction.rightHalf.rawValue == "rightHalf")
        #expect(WindowAction.maximize.rawValue == "maximize")
        #expect(WindowAction.minimize.rawValue == "minimize")
        #expect(WindowAction.allCases.count == 4)
    }
}
