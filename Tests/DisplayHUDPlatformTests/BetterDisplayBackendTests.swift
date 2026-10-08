import Testing
@testable import DisplayHUDPlatform

private actor RecordingBetterDisplayTransport: BetterDisplayTransport {
    struct Request: Equatable, Sendable {
        let commands: [String]
        let parameters: [String: String?]
    }

    private(set) var requests: [Request] = []

    func send(
        commands: [String],
        parameters: [String: String?],
        timeout: Duration
    ) async throws -> String? {
        requests.append(Request(commands: commands, parameters: parameters))
        return "0.378"
    }
}

@Test("BetterDisplay receives an absolute combined-brightness target and readback")
func betterDisplayUsesAbsoluteCombinedBrightness() async throws {
    let transport = RecordingBetterDisplayTransport()
    let backend = BetterDisplayBackend(transport: transport)
    let display = DisplayIdentifier(rawValue: 4)

    let confirmed = try await backend.setBrightness(
        BasisPoints(percent: 37.8),
        for: display
    )

    #expect(confirmed.percent == 37.8)
    #expect(await transport.requests == [
        .init(
            commands: ["set", "get"],
            parameters: [
                "displayID": "4",
                "combinedBrightness": "37.80%",
            ]
        )
    ])
}
