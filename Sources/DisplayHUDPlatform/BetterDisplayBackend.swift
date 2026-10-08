import Foundation
import DisplayHUDCore

public protocol BetterDisplayTransport: Sendable {
    func send(
        commands: [String],
        parameters: [String: String?],
        timeout: Duration
    ) async throws -> String?
}

public enum BetterDisplayError: Error, Equatable {
    case invalidPayload
}

public actor BetterDisplayBackend: BrightnessBackend {
    private let transport: any BetterDisplayTransport
    private let timeout: Duration

    public init(
        transport: any BetterDisplayTransport,
        timeout: Duration = .milliseconds(250)
    ) {
        self.transport = transport
        self.timeout = timeout
    }

    public func readBrightness(for display: DisplayIdentifier) async throws -> BasisPoints {
        let payload = try await transport.send(
            commands: ["get"],
            parameters: [
                "displayID": String(display.rawValue),
                "combinedBrightness": nil,
            ],
            timeout: timeout
        )
        return try Self.parseBrightness(payload)
    }

    public func setBrightness(
        _ value: BasisPoints,
        for display: DisplayIdentifier
    ) async throws -> BasisPoints {
        let payload = try await transport.send(
            commands: ["set", "get"],
            parameters: [
                "displayID": String(display.rawValue),
                "combinedBrightness": String(
                    format: "%.2f%%",
                    locale: Locale(identifier: "en_US_POSIX"),
                    value.percent
                ),
            ],
            timeout: timeout
        )
        return try Self.parseBrightness(payload)
    }

    private static func parseBrightness(_ payload: String?) throws -> BasisPoints {
        guard let payload,
              let scalar = Double(payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              scalar.isFinite
        else {
            throw BetterDisplayError.invalidPayload
        }
        return BasisPoints(scalar: scalar)
    }
}
