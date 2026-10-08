import Testing
@testable import DisplayHUDCore

private actor AvailabilitySequence {
    private var outcomes: [Bool]
    private(set) var attempts = 0

    init(_ outcomes: [Bool]) {
        self.outcomes = outcomes
    }

    func probe() -> Bool {
        attempts += 1
        return outcomes.isEmpty ? false : outcomes.removeFirst()
    }
}

@Test("Login readiness recovers after a backend starts late")
func loginReadinessRecoversAfterTransientFailures() async {
    let sequence = AvailabilitySequence([false, false, true])
    let recovery = BoundedAvailabilityRecovery(
        retryDelays: [.zero, .zero]
    )

    let recovered = await recovery.run {
        await sequence.probe()
    }

    #expect(recovered)
    #expect(await sequence.attempts == 3)
}

@Test("Login readiness stops after its finite retry schedule")
func loginReadinessStopsAfterFiniteRetries() async {
    let sequence = AvailabilitySequence([false, false, false, true])
    let recovery = BoundedAvailabilityRecovery(
        retryDelays: [.zero, .zero]
    )

    let recovered = await recovery.run {
        await sequence.probe()
    }

    #expect(!recovered)
    #expect(await sequence.attempts == 3)
}
