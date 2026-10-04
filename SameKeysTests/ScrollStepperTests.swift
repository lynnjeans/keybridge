import Testing

@Suite struct ScrollStepperTests {
    typealias Input = (direction: ScrollDirection, source: ScrollSource, lines: Double, ms: UInt64)

    /// Feeds the inputs to a fresh stepper and returns whether each made a step.
    func steps(_ inputs: [Input]) -> [Bool] {
        var stepper = ScrollStepper()
        return inputs.map {
            stepper.step(direction: $0.direction, source: $0.source, lines: $0.lines, timestamp: $0.ms * 1_000_000)
        }
    }

    @Test func everyNotchIsAStep() {
        let notches: [Input] = (0..<5).map { (.up, .notchedWheel, 1, UInt64($0) * 10) }
        #expect(steps(notches) == [true, true, true, true, true])
    }

    @Test func smoothTravelAddsUpToAStep() {
        // Three 0.4-line movements make one step with 0.2 left over, which
        // 0.8 more turns into the next.
        #expect(steps([
            (.up, .smoothWheel, 0.4, 0),
            (.up, .smoothWheel, 0.4, 10),
            (.up, .smoothWheel, 0.4, 20),
            (.up, .smoothWheel, 0.8, 30),
        ]) == [false, false, true, true])
    }

    @Test func changingDirectionStartsOver() {
        #expect(steps([
            (.up, .smoothWheel, 0.9, 0),
            (.down, .smoothWheel, 0.9, 10),
            (.down, .smoothWheel, 0.1, 20),
        ]) == [false, false, true])
    }

    @Test func aPauseDropsPartialTravel() {
        #expect(steps([
            (.up, .smoothWheel, 0.9, 0),
            (.up, .smoothWheel, 0.9, 400),
        ]) == [false, false])
    }
}
