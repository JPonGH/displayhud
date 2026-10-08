import Testing
@testable import DisplayHUDCore

@Test("A directional half-percent step normalizes off-grid values without reversing direction")
func directionalStepNormalizesOffGridValues() {
    #expect(BasisPoints(percent: 37.3).nextHalfPercent(in: .increase).percent == 37.5)
    #expect(BasisPoints(percent: 37.3).nextHalfPercent(in: .decrease).percent == 37.0)
    #expect(BasisPoints(percent: 37.5).nextHalfPercent(in: .increase).percent == 38.0)
    #expect(BasisPoints(percent: 37.5).nextHalfPercent(in: .decrease).percent == 37.0)
}

@Test("Twenty thousand randomized directional transitions land on the half-percent grid")
func randomizedTransitionsNormalizeWithoutOvershooting() {
    var seed: UInt64 = 0xD15A_1A7

    for _ in 0..<20_000 {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        let current = BasisPoints(rawValue: Int(seed % 10_001))
        let direction: StepDirection = (seed & 1) == 0 ? .increase : .decrease
        let result = current.nextHalfPercent(in: direction)

        #expect(result.rawValue % 50 == 0)
        switch direction {
        case .increase:
            #expect(result >= current)
            #expect(result.rawValue - current.rawValue <= 50)
            if current < .maximum, current.rawValue % 50 == 0 {
                #expect(result.rawValue - current.rawValue == 50)
            }
        case .decrease:
            #expect(result <= current)
            #expect(current.rawValue - result.rawValue <= 50)
            if current > .minimum, current.rawValue % 50 == 0 {
                #expect(current.rawValue - result.rawValue == 50)
            }
        }
    }
}

@Test("Fixed-point boundaries clamp without wrapping")
func transitionsClampAtBoundaries() {
    #expect(BasisPoints(percent: 99.8).nextHalfPercent(in: .increase) == .maximum)
    #expect(BasisPoints(percent: 0.2).nextHalfPercent(in: .decrease) == .minimum)
    #expect(BasisPoints.maximum.nextHalfPercent(in: .increase) == .maximum)
    #expect(BasisPoints.minimum.nextHalfPercent(in: .decrease) == .minimum)
}
